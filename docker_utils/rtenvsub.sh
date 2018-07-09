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
# shellcheck source=../shtdlib.sh
source "$(dirname "${0}")/../shtdlib.sh"

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

OPTIONS:
   -p, --process                    Process name to signal if config files change
   -s, --signal                     Signal to send (defaults to HUP, see man kill for details)
   -o, --overlay                    Set up mirror even if the destination directory contains files/subdirectories
   -h, --help                       Show this message
   -v, --verbose {verbosity_level}  Set verbose mode (optionally accepts a integer level)

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
            process="${OPTARG}"
            debug 5 "Set process name to signal to: ${process}"
        ;;
        's'|'signal')
            signal="${OPTARG}"
            debug 5 "Set signal to: ${signal}"
        ;;
        'o'|'overlay')
            overlay='true'
            debug 5 "Overlay enabled!"
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
while getopts ":-:p:s:ovh" opt; do
    parse_arguments "${opt}"
done
#non_argument_parameters=( "${@##\-*}" )
declare -a non_argument_parameters
remaining_parameters=( "${@##\-*}" )
for i in "${remaining_parameters[@]}"; do
    if [ -n "${i}" ] ; then
        non_argument_parameters+=( "${i}" )
    fi
done
debug 10 "Non-argument parameters:" "${non_argument_parameters[*]}"

if [ "${#@}" -lt 2 ] ; then
    color_echo red "You need to supply at least one source dir/file and a destination directory"
    print_usage
    exit 64
fi
export signal="${signal:-SIGHUP}"
export process="${process:-}"
export overlay="${overlay:-'false'}"

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
        full_path="$(readlink -m "${path}")"
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
                if [ -n "${file}" ] ; then
                    add_on_sig "rm -f ${destination}/${file#${full_path}}"
                    setup_named_pipe "${destination}" "${file}" "${full_path}" &> "${console}" &
                else
                    color_echo red "EMPTY FILE!"
                    exit 1
                fi
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
                            killall -"${signal}" "${process}"
                        fi
                    ;;
                    'MOVED_TO'|'CREATE') # New file events
                        debug 6 "New file event on: ${dir_file_events[*]0:1} ${event}"
                        create_directory_structure "${destination}" "${dir_file_events[0]}" "${full_path}"
                        setup_named_pipe "${destination}" "${dir_file_events[0]}/${dir_file_events[1]}" "${full_path}" &
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
                    ;;
                    'DELETE_SELF'|'UNMOUNT') # Stop/exit/cleanup events
                        color_echo red "Received fatal event: ${dir_file_events[0:1]} ${event}, exiting!"
                        exit 1
                    ;;
                esac
            done
        done
    done
}

# Call the main mirroring function
mirror_envsubst_path "${non_argument_parameters[@]}"
