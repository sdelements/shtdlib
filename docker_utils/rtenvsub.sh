#!/bin/bash
#
# Copyright (c) 2018 SD Elements Inc.
#
#  All Rights Reserved.
#
# NOTICE:  All information contained herein is, and remains
# the property of SD Elements Incorporated and its suppliers,
# if any.  The intellectual and technical concepts contained
# herein are proprietary to SD Elements Incorporated
# and its suppliers and may be covered by U.S., Canadian and other Patents,
# patents in process, and are protected by trade secret or copyright law.
# Dissemination of this information or reproduction of this material
# is strictly forbidden unless prior written permission is obtained
# from SD Elements Inc..
# Version

version='0.1'

# Set a safe umask
umask 0077

default_library_name='shtdlib.sh'
default_base_download_url='https://raw.githubusercontent.com/sdelements/shtdlib/master'
default_install_path='/usr/local/bin'

# Temporary debug function
type -t import | grep -q '^function$' || function debug { echo "${@:2}" ; }

# Import or source
function import_or_source {
    if type -t import | grep -q '^function$' ; then
        debug 10 "Importing ${0}"
        import "${1}"
    else
        debug 10 "Sourcing ${0}"
        # shellcheck disable=1090
        source "${1}"
    fi
}

# Library download function, optionally accepts a full path/name and URL
function download_lib {
    local tmp_path="${1:-$(mktemp)}"
    local lib_url="${2:-${default_base_download_url}/${default_library_name}}"
    curl -s -l -o "${tmp_path}" "${lib_url}" || wget --no-verbose "${lib_url}" --output-document "${tmp_path}" || return 1
}

# Library install function, optionallly accepts a URL and a full path/name
# shellcheck disable=SC2120,SC2119
function install_lib {
    local lib_path="${1:-${default_install_path}/${default_library_name}}"
    local lib_name="${2:-$(basename "${lib_path}")}"
    local tmp_path="${3:-$(mktemp)}"

    echo "Installing library ${lib_name} to ${lib_path}"
    download_lib "${tmp_path}" "${default_base_download_url}/${lib_name}"
    mv "${tmp_path}" "${lib_path}" || sudo mv "${tmp_path}" "${lib_path}" || return 1
    chmod 755 "${lib_path}" || sudo chmod 755 "${lib_path}" || return 1
    import_or_source "${lib_path}"
    color_echo green "Installed ${lib_name} to ${lib_path} successfully"
}

# Library import function, accepts one optional parameter, name of the file to import
# shellcheck disable=SC2120,SC2119
function import_lib {
    local full_path
    local lib_name="${1:-${default_library_name}}"
    local lib_no_ext="${lib_name%.*}"
    local lib_basename_s="${lib_no_ext##*/}"
    full_path="$(readlink -f "${BASH_SOURCE[0]}" 2> /dev/null || realpath "${BASH_SOURCE[0]}" 2> /dev/null || greadlink -f "${BASH_SOURCE[0]}" 2> /dev/null || true)"
    full_path="${full_path:-${0}}"
    # Search current dir and walk down to see if we can find the library in a
    # parent directory or sub directories of parent directories named lib/bin
    while true; do
        local pref_pattern=( "${full_path}/${lib_name}" "${full_path}/${lib_basename_s}/${lib_name}" "${full_path}/lib/${lib_name}" "${full_path}/bin/${lib_name}" )
        for pref_lib in "${pref_pattern[@]}" ; do
            if [ -e "${pref_lib}" ] ; then
                debug 10 "Found ${pref_lib}, attempting to import/source"
                import_or_source "${pref_lib}" && return 0
                echo "Unable to import/source ${pref_lib}!"
            fi
        done
        full_path="$(dirname "${full_path}")"
        if [ "${full_path}" == '/' ] ; then
            # If we haven't found the library try the PATH or install if needed
            debug 10 "Attempting to import/source ${lib_name}"
            import_or_source "${lib_name}" 2> /dev/null || install_lib "${default_install_path}/${lib_name}" "${lib_name}" && return 0
            # If nothing works then we fail
            echo "Unable to import ${lib_name}"
            return 1
        fi
    done
}

# Import the shell standard library
# shellcheck disable=SC2119
import_lib

debug 10 "Running ${0} with PID: ${$}"

if ! whichs envsubst ; then
    color_echo red "Unable to locate envsubst command, please make sure it's available"
    color_echo cyan 'Perhaps this can be fixed with: apt-get -y install gettext-base'
    exit 1
fi
if ! whichs inotifywait ; then
    color_echo red "Unable to locate the inotifywait command, please make sure it's available"
    color_echo cyan 'Perhaps this can be fixed with: apt-get install inotify-tools'
    exit 1
fi

# Print usage and argument list
function print_usage {
cat << EOF
usage: ${0} destination_path file(s) director(y/ies)

rtenvsub

Real time environment variable based templating engine

This script uses the Linux inotify interface in combination with the envsubst
program and optionally named pipes to mirror directories and files replacing environment
variables in realtime in an efficent manner. In addition any changes to the
template files can trigger service/process reload or restart by signaling them
(default SIGHUP).

To refresh environment variables loaded by this script you can send it the HUP signal.

For more info see:

man inotifywait
man mkfifo
man envsubst
man kill
man pgrep/pkill

OPTIONS:
   -p, --process                    Process PID or name to signal if config files change
   -s, --signal                     Signal to send (defaults to HUP, see man kill for details)
   -o, --overlay                    Set up mirror even if the destination directory contains files/subdirectories
   -n, --nofifo                     Write to files instead of using named pipes
   -h, --help                       Show this message
   -d, --daemon                     Daemonize, run in the background
   -v, --verbose {verbosity_level}  Set verbose mode (optionally accepts a integer level)
   -t, --test                       Run unit tests

Examples:
${0} /etc/nginx /usr/share/doc/nginx # Recursively map all files and directories from /usr/share/doc/nginx to /etc/nginx
${0} /etc /usr/share/doc/ntp.conf -p ntpd # Map /usr/share/doc/ntp.conf to /etc/ntp.conf and send a HUP signal to the ntpd process if the file changes

Version: ${version:-${shtdlib_version}}
EOF
}

# Parse command line arguments
function parse_arguments {
    debug 5 "Parse Arguments got argument: ${1}"
    case ${1} in
        '-')
            # This uses the parse_arguments logic to parse a tag and it's value
            # The value is passed on in the OPTARG variable which is standard
            # when parsing arguments with optarg.
            tag="${OPTARG}"
            debug 10 "Found long argument/option"
            parse_opt_arg OPTARG ''
            parse_arguments "${tag}"
        ;;
        'p'|'process')
            export process="${OPTARG}"
            debug 5 "Set process name to signal to: ${process}"
        ;;
        's'|'signal')
            export signal="${OPTARG}"
            debug 5 "Set signal to: ${signal}"
        ;;
        'o'|'overlay')
            overlay='true'
            debug 5 "Overlay enabled!"
        ;;
        'n'|'nofifo')
            nofifo='true'
            debug 5 "Named pipes disabled, using files instead!"
        ;;
        'd'|'daemon')
            daemonize='true'
            debug 5 "Daemon mode selected!"
        ;;
        'v'|'verbose')
            parse_opt_arg verbosity '10'
            export verbose=true
            # shellcheck disable=SC2154
            debug 1 "Set verbosity to: ${verbosity}"
        ;;
        'h'|'help'|'version')    # Help
            print_usage
            exit 0
        ;;
        't'|'test')    # Unit tests
            run_unit_tests='true'
        ;;
        '?')    # Invalid option specified
            color_echo red "Invalid option '${OPTARG}'"
            print_usage
            exit 64
        ;;
        ':')    # Expecting an argument but none provided
            color_echo red "Missing option argument for option '${OPTARG}'"
            print_usage
            exit 64
        ;;
        '*')    # Anything else
            color_echo red "Unknown error while processing options"
            print_usage
            exit 64
        ;;
    esac
}

# Process arguments/parameters/options
while getopts ":-:p:s:ndotvh" opt; do
    parse_arguments "${opt}"
done
all_arguments=( "${@}" )
declare -a non_argument_parameters
for (( index=${#@}-1 ; index>=0 ; index-- )) ; do
        # shellcheck disable=SC2004
	if ! [[ "${all_arguments[$index]}" =~ -[-:alphanum:]* ]] && ! in_array "${all_arguments[$(($index - 1))]}" '--signal' '--process' '--verbose' '-p' '-s' '-v' ; then
            non_argument_parameters[(${index})]="${all_arguments[${index}]}"
        else
            break
        fi
done
debug 10 "Non-argument parameters:" "${non_argument_parameters[*]:-}"

export run_unit_tests="${run_unit_tests:-false}"
export signal="${signal:-SIGHUP}"
export process="${process:-}"
export overlay="${overlay:-false}"
export daemonize="${daemonize:-false}"
export nofifo="${nofifo:-false}"

if [ "${#@}" -lt 2 ] && ! "${run_unit_tests}" ; then
    color_echo red "You need to supply at least one source dir/file and a destination directory"
    print_usage
    exit 64
fi

# Create a named pipe and set up envsubst loop to feed it
function setup_named_pipe {
    local destination="${1}"
    local file="${2}"
    local path="${3}"
    debug 10 "Creating named pipe: ${destination}/${file#${path}} with permissions identical to ${file}"
    # Create a named pipe for each file with same permissions, then
    # set up an inotifywait process to monitor and trigger envsubst
    mkfifo -m "$(stat -c '%a' "${file}")" "${destination}/${file#${path}}"

    # Loop envsubst until the destination or source file no longer exist
    while [ -d "${destination}" ] && [ -f "${file}" ] ; do
        render_file "${destination}" "${file}" "${path}}"
    done
}

# Render configuratin template to a file using envsubst
function render_file {
    local destination="${1}"
    local file="${2}"
    local path="${3}"
    debug 10 "Rendering file: ${destination}/${file#${path}} from template: ${file}"
    envsubst < "${file}" > "${destination}/${file#${path}}" "$(compgen -v | sed -e 's/^/\$/g' | tr '\n' ',')"
}

# Create a directory to mirror a source
# shellcheck disable=SC2174
function create_directory_structure {
    local destination="${1}"
    local dir="${2}"
    local path="${3}"
    debug 10 "Creating directory ${destination}/${dir#${path}} with permissions identical to ${dir}"
    # Create each directory in the mirror with same permissions
    mkdir -m "$(stat -c '%a' "${dir}")" -p "${destination}/${dir#${path}}"
}

# Loops inotify on a given source and makes sure it's mirrored and templates
# rendered to the destination
function inotify_looper  {
    local destination="${1}"
    local full_path="${2}"
    # Set up notifications for each path and fork watching
    inotifywait --monitor --recursive --format '%w %f %e' "${full_path}" \
        --event 'modify' --event 'close_write' \
        --event 'moved_to' --event 'create' \
        --event 'moved_from' --event 'delete' --event 'move_self' \
        --event 'delete_self' --event 'unmount' \
            | while read -r -a dir_file_events; do
        for event in "${dir_file_events[@]:2}"; do
            case "${event}" in
                'ACCESS'|'CLOSE_NOWRITE'|'OPEN') #Non events
                    color_echo red "Non mutable event on: ${dir_file_events[*]}, this should not happen since we don't subscribe to these"
                    exit 1
                ;;
                'MODIFY'|'CLOSE_WRITE') # File modified events
                    debug 6 "File modification event on: ${dir_file_events[*]}"
                    if [ -n "${process}" ] ; then
                        signal_process "${process}" "${signal}"
                    fi
                    if ${nofifo} ; then
                        render_file "${destination}" "${dir_file_events[0]}/${dir_file_events[1]}" "${full_path}"
                    fi
                ;;
                'MOVED_TO'|'CREATE') # New file events
                    debug 6 "New file event on: ${dir_file_events[*]} ${event}"
                    create_directory_structure "${destination}" "${dir_file_events[0]}" "${full_path}"
                    if [ -n "${process}" ] ; then
                        signal_process "${process}" "${signal}"
                    fi
                    if ${nofifo} ; then
                        render_file "${destination}" "${dir_file_events[0]}/${dir_file_events[1]}" "${full_path}"
                    else
                        setup_named_pipe "${destination}" "${dir_file_events[0]}/${dir_file_events[1]}" "${full_path}" &
                    fi
                ;;
                'MOVED_FROM'|'DELETE'|'MOVE_SELF') # File/Directory deletion events
                    fs_object="${dir_file_events[0]}/${dir_file_events[1]}"
                    mirror_object="${destination}/${fs_object#${full_path}}"
                    debug 5 "Filesystem object removed from source, removing from mirror"
                    debug 5 "Source: ${fs_object} Pipe: ${mirror_object}"
                    if [ -f "${fs_object}" ] ; then
                        rm -f "${mirror_object}"
                    elif [ -d "${fs_object}" ] ; then
                        rmdir "${mirror_object}"
                    fi
                    if [ -n "${process}" ] ; then
                        signal_process "${process}" "${signal}"
                    fi
                ;;
                'DELETE_SELF'|'UNMOUNT') # Stop/exit/cleanup events
                    color_echo red "Received fatal event: ${dir_file_events[0:1]} ${event}, exiting!"
                    if [ -n "${process}" ] ; then
                        signal_process "${process}" "${signal}"
                    fi
                    exit 1
                ;;
            esac
        done
    done
}


# Mirrors given path(s) of directories and files to a destination path using named
# pipes or files substituting environment variables found in files in realtime
# Ignores filesystem objects that are neither files or directories
function mirror_envsubst_paths {
    declare -a sources
    destination="$(readlink -m "${1}")"
    sources=("${@:2}")
    if ! [ -d "${destination}" ] ; then
        color_echo red "Destination path: ${destination} is not a directory, exiting!"
        exit 1
    fi
    declare -a looper_pids
    # Iterate over each source file/directory, exclude root dir if specified
    for path in "${sources[@]}"; do
        if ! [ -e "${path}" ] ; then
            color_echo red "Source path: ${path} does not exist, exiting!"
            exit 1
        fi
        full_path="$(readlink -m "${path}")"

        if [ "${full_path#${destination}}" != "${full_path}" ] || [ "${destination#${full_path}}" != "${destination}" ] ; then
            color_echo red "Source/Destination directories can't be subdirectories of each other or the same directory"
            exit 64
        fi

        mapfile -t directories < <(find "${full_path}" -mindepth 1 -type d -exec readlink -m {} \;)
        mapfile -t files < <(find "${full_path}" -type f -exec readlink -m {} \;)

        # Create directory structure, check if destination is empty
        if [ -n "$(ls -A "${destination}")" ] && ! ${overlay} ; then
            color_echo red "Destination directory is not empty, if you still want to overlay into it please use the -o/--overlay option"
            print_usage
            exit 1
        else
            for dir in "${directories[@]}"; do
                create_directory_structure "${destination}" "${dir}" "${full_path}"
            done

        fi

        # Create named pipes / files and set up cleanup on signals for them
        if [ -z "${files[*]}" ] ; then
            color_echo magenta "Destination directory does not contain any files, no pipes created for ${full_path}!"
        else
            for file in "${files[@]:-}"; do
                add_on_sig "rm -f ${destination}${file#${full_path}}"
                if ${nofifo} ; then
                    render_file "${destination}" "${file}" "${full_path}"
                else
                    setup_named_pipe "${destination}" "${file}" "${full_path}" &
                fi
            done
        fi

        # Set up safe cleanup for directory structure (needs to be done in
        # reverse order to ensure safety of operation without recursive rm
        local index
        for (( index=${#directories[@]}-1 ; index>=0 ; index-- )) ; do
            add_on_sig "rmdir ${destination}${directories[${index}]#${full_path}}"
        done

        # Run update loop and detach it
        if ${daemonize} ; then
            inotify_looper "${destination}" "${full_path}" &
        else
            inotify_looper "${destination}" "${full_path}" &
        fi
        looper_pids+=( "${!}" )
    done
    if ! ${daemonize} ; then
        debug 8 "Waiting for looper pids: ${looper_pids[*]}"
        wait "${looper_pids[*]}"
    fi
}

# Unit tests
# shellcheck disable=SC2046,SC2154,SC2016,SC2034,SC2064
function unit_tests {
    export verbosity=10
    debug 5 "Running unit tests!"
    # Basic setup
    export TEST_VARIABLE1='/dev/null'
    export TEST_VARIABLE2='example.com'
    create_secure_tmp tmp_source_test_dir 'dir'
    create_secure_tmp tmp_dest_test_dir 'dir'
    create_secure_tmp tmp_source_test_file 'file' "${tmp_source_test_dir}"
    test_string=$(tr -dc '[:alnum:]' < /dev/urandom | fold -w 1024 | head -n 1)
    export signal='SIGUSR1'
    # Set up a proces to listen to signals and perform actions
    signal_test_file="${tmp_source_test_dir}/signal_test_file"
    process="$(signal_processor "${signal}"  "test -f ${signal_test_file} && echo ${test_string} > ${signal_test_file}")"
    export process

    # Test setting up a named pipe
    setup_named_pipe "${tmp_dest_test_dir}" "${tmp_source_test_file}" "${tmp_source_test_dir}" &
    echo "${test_string}" > "${tmp_source_test_file}" &
    sleep 1
    read_test_string="$(cat "${tmp_dest_test_dir}/${tmp_source_test_file#${tmp_source_test_dir}}")"
    assert [ "${test_string}" == "${read_test_string}" ]

    # Test creating directory structure
    mkdir "${tmp_source_test_dir}/sub_dir"
    create_directory_structure "${tmp_dest_test_dir}" "${tmp_source_test_dir}/sub_dir" "${tmp_source_test_dir}"
    assert [ "$(basename $(find "${tmp_dest_test_dir}" -mindepth 1 -type d))" == "$(basename $(find  "${tmp_source_test_dir}" -mindepth 1 -type d))" ]

    # Test mirroring a more complicated structure
    create_secure_tmp tmp_mirror_test_dir 'dir'
    mkdir "${tmp_source_test_dir}/sub_dir/sub_sub_dir"
    touch "${tmp_source_test_dir}/test_file"
    touch "${tmp_source_test_dir}/sub_dir/sub_file"
    touch "${tmp_source_test_dir}/sub_dir/sub_sub_dir/sub_sub_file"

    mirror_envsubst_paths "${tmp_mirror_test_dir}" "${tmp_source_test_dir}" &

    sleep 1
    mapfile -t files < <(find "${tmp_source_test_dir}" -type f)
    mapfile -t pipes < <(find "${tmp_mirror_test_dir}" -type p)
    assert [ "${#files}" -eq "${#pipes}" ]

    # Check each file matches
    for (( index=0 ; index<${#files[@]} ; index++ )) ; do
        assert diff "${files[${index}]}" "${pipes[${index}]}"
    done

    # Test dynamically adding a file with variables
    echo 'setting1=${TEST_VARIABLE1}' > "${tmp_source_test_dir}/settings_file"
    sleep 1
    assert [ "$(cat "${tmp_mirror_test_dir}/settings_file")" == "$(cat "${tmp_mirror_test_dir}/settings_file")" ]
    echo 'setting2=$TEST_VARIABLE2' >> "${tmp_source_test_dir}/settings_file"
    sleep 1
    assert [ "$(cat "${tmp_mirror_test_dir}/settings_file")" == "$(cat "${tmp_mirror_test_dir}/settings_file")" ]

    # Test signaling
    touch "${tmp_source_test_dir}/signal_test_file"
    sleep 1
    assert test -f "${tmp_source_test_dir}/signal_test_file"
    test_string_from_trap="$(cat "${signal_test_file}")"
    assert [ "${test_string_from_trap}" == "${test_string}" ]
    color_echo green "All tests successfully completed"
    # Make sure all descendant processes get terminated
    kill $(pgrep --pgroup "${$}" | grep -v "${0}")
    exit 0
}

# Run tests or not
if ${run_unit_tests} ; then
    unit_tests
fi

# Call the main mirroring function
if ${daemonize} ; then
    mirror_envsubst_paths "${non_argument_parameters[@]:-}" &
    wait "${!}"
else
    mirror_envsubst_paths "${non_argument_parameters[@]:-}"
fi
