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

# Log/Console destination
console="$(tty || logger || false)"

# Import the standard shell library
# shellcheck source=../shtdlib.sh disable=SC1091
source "$(dirname "${0}")/../shtdlib.sh" &> /dev/null || ../shtdlib.sh &> /dev/null || source ./shtdlib.sh &> /dev/null || source shtdlib.sh


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

This script uses the Linux inotify interface in combination with named pipes
and the envsubst program to mirror directories and files replacing environment
variables in realtime in an efficent manner. In addition any changes to the
template files can trigger service/process reload or restart by signaling them
(default SIGHUP).

To refresh environment variables loaded by this script you can set it the HUP signal.

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
while getopts ":-:p:s:dotvh" opt; do
    parse_arguments "${opt}"
done
declare -a non_argument_parameters
remaining_parameters=( "${@##\-*}" )
for i in "${remaining_parameters[@]}"; do
    if [ -n "${i}" ] ; then
        non_argument_parameters+=( "${i}" )
    fi
done
debug 10 "Non-argument parameters:" "${non_argument_parameters[*]}"

if [ "${#@}" -lt 2 ] && ! "${run_unit_tests}" ; then
    color_echo red "You need to supply at least one source dir/file and a destination directory"
    print_usage
    exit 64
fi
export run_unit_tests="${run_unit_tests:-false}"
export signal="${signal:-SIGHUP}"
export process="${process:-}"
export overlay="${overlay:-false}"
export daemonize="${daemonize:-false}"

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
        envsubst < "${file}" > "${destination}/${file#${path}}"
    done
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

# Mirrors a given path of directories and files to a second path using named
# pipes and substituting environment variables found in files in realtime
# Ignores filesystem objects that are neither files or directories
function mirror_envsubst_path {
    declare -a sources
    destination="$(readlink -m "${1}")"
    sources=("${@:2}")
    if ! [ -d "${destination}" ] ; then
        color_echo red "Destination path: ${destination} is not a directory, exiting!"
        exit 1
    fi
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

        # Create named pipes and set up cleanup on signals for them
        if [ -z "${files[*]}" ] ; then
            color_echo magenta "Destination directory does not contain any files, no pipes created for ${full_path}!"
        else
            for file in "${files[@]:-}"; do
                add_on_sig "rm -f ${destination}/${file#${full_path}}"
                setup_named_pipe "${destination}" "${file}" "${full_path}" &> "${console}" &
            done
        fi

        # Set up safe cleanup for directory structure (needs to be done in
        # reverse order to ensure safety of operation without recursive rm
        local index
        for (( index=${#directories[@]}-1 ; index>=0 ; index-- )) ; do
            add_on_sig "rmdir ${destination}/${directories[index]#${full_path}}"
        done


        # Set up notifications for each path and fork watching
        inotifywait --monitor --recursive --format '%w %f %e' "${full_path}"\
            --event 'modify' --event 'close_write'\
            --event 'moved_to' --event 'create'\
            --event 'moved_from' --event 'delete' --event 'move_self'\
            --event 'delete_self' --event 'unmount'\
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
                    ;;
                    'MOVED_TO'|'CREATE') # New file events
                        debug 6 "New file event on: ${dir_file_events[*]0:1} ${event}"
                        create_directory_structure "${destination}" "${dir_file_events[0]}" "${full_path}"
                        setup_named_pipe "${destination}" "${dir_file_events[0]}/${dir_file_events[1]}" "${full_path}" &
                        if [ -n "${process}" ] ; then
                            signal_process "${process}" "${signal}"
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
    done
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
    setup_named_pipe "${tmp_dest_test_dir}" "${tmp_source_test_file}" "${tmp_source_test_dir}" &> "${console}" &
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

    mirror_envsubst_path "${tmp_mirror_test_dir}" "${tmp_source_test_dir}" &

    sleep 1
    mapfile -t files < <(find "${tmp_source_test_dir}" -type f)
    mapfile -t pipes < <(find "${tmp_mirror_test_dir}" -type p)
    assert [ "${#files}" -eq "${#pipes}" ]

    for (( index=${#files[@]}-1 ; index>=0 ; index-- )) ; do
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
    mirror_envsubst_path "${non_argument_parameters[@]}" &> "${console}" &
else
    mirror_envsubst_path "${non_argument_parameters[@]}"
fi
