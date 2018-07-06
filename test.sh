#!/bin/bash

# Version
version='0.1'

# Set a safe umask
umask 0077

# Set strict mode
set -euo pipefail

# Store original tty
init_tty="$(tty || true)"

# Default verbosity, common levels are 0,1,5,10
verbosity="${verbosity:-1}"

# Timestamp, the date/time we started
start_timestamp="$(date +"%Y%m%d%H%M")"

# Color Constants
export black='\e[0;30m'
export red='\e[0;31m'
export green='\e[0;32m'
export yellow='\e[0;33m'
export blue='\e[0;34m'
export magenta='\e[0;35m'
export purple="${magenta}" # Alias
export cyan='\e[0;36m'
export white='\e[0;37m'
export blank='\e[0m' # No Color

# Colored echo
# takes color and message as parameters, valid colors are listed in the constants section
function color_echo {
    printf "${!1}%s${blank}\\n" "${2}"
}

# Debug method for verbose debugging
# Note debug is special because it's safe even in subshells because it bypasses
# the stdin/stdout and writes directly to the terminal
function debug {
    if [ "${verbosity}" -ge "${1}" ]; then
        if [ -e "${init_tty}" ] ; then
            color_echo yellow "${@:2}" > "${init_tty}"
        else
            color_echo yellow "${@:2}"
        fi
    fi
}

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
   -p, --process      Process name to signal if config files change
   -s, --signal                     Signal to send (defaults to HUP, see man kill for details)
   -h, --help                       Show this message
   -v, --verbose {verbosity_level}  Set verbose mode (optionally accepts a integer level)

Examples:
${0} /etc/nginx /usr/share/doc/nginx # Recursively map all files and directories from /usr/share/doc/nginx to /etc/nginx
${0} /etc /usr/share/doc/ntp.conf -p ntpd # Map /usr/share/doc/ntp.conf to /etc/ntp.conf and send a HUP signal to the ntpd process if the file changes

Version: ${version:-${shtdlib_version}}
EOF
}

# Parse for optional arguments (-f vs. -f optional_argument)
# Takes variable name as first arg and default value as optional second
# variable will be initialized in any case for compat with -e
parameter_array=("${@-()}") # Store all parameters as an array
function parse_opt_arg {
    # Pick up optional arguments
    debug 10 "Parameter Array is: ${parameter_array[*]}"
    debug 10 "Option index is: ${OPTIND}"
    next_arg="${parameter_array[$((OPTIND - 1))]:-}"
    debug 10 "Optarg index is: ${OPTIND} and next argument is: ${next_arg}"
    if [ "$(echo "${next_arg}" | grep -v '^-')" != "" ]; then
            debug 10 "Found optional argument and setting ${1}=\"${next_arg}\""
            eval "${1}=\"${next_arg}\""
            # Skip over the optional value so getopts does not stop processing
            (( OPTIND++ ))
    else
            if [ "${2}" != '' ]; then
                debug 10 "Optional argument not found, using default and setting ${1}=\"${2}\""
                eval "${1}=\"${2}\""
            else
                debug 10 "Initializing empty variable ${1}"
                eval "${1}="
            fi
    fi
    unset next_arg
    color_echo cyan "Set argument: ${1} to \"${!1}\""
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
        'v'|'verbose')
            parse_opt_arg verbosity '10'
            export verbose=true
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
signal="${signal:-SIGHUP}"
process="${process:-}"

# Process arguments/parameters/options
while getopts ":-:p:s:vh" opt; do
    parse_arguments "${opt}"
done

# Create a named pipe and set up envsubst loop to feed it
function setup_named_pipe {
    local destination="${1}"
    local file"${2}"
    local path="${3}"

    # Create a named pipe for each file with same permissions, then
    # set up an inotifywait process to monitor and trigger envsubst
    mkfifo -m "$(stat -f '%p' "${file}")" -p "${destination}/${file#${path}}"

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
    # Create each directory in the mirror with same permissions
    mkdir -m "$(stat -f '%p' "${dir}")" -p "${destination}/${dir#${path}}"
}

# Mirrors a given path of directories and files to a second path using named
# pipes and substituting environment variables found in files in realtime
# Ignores filesystem objects that are neither files or directories
function mirror_envsubst_path {
    local destination="${1}"
    local sources=("${1[@]:1}")
    if ! [ -d "${destination}" ] ; then
        color_echo red "Destination path: ${destination} is not a directory, exiting!"
        exit 1
    fi
    # Iterate over each source file/directory
    for path in "${sources[@]}"; do
        mapfile -t directories < <(find "${path}" -type d)
        mapfile -t files < <(find "${path}" -type f)

        for dir in "${directories[@]}"; do
            create_directory_structure "${destination}" "${dir}" "${path}"
        done

        for file in "${files[@]}"; do
            setup_named_pipe "${destination}" "${file}" "${path}" &
        done

        # Set up notifications for each path and fork them, register signal
        # handlers for each as needed
        inotifywait --monitor --recursive --format'%w %f %e' "${path}" | while read -r -a dir_file_events; do
            for event in "${dir_file_events[@]:2}"; do
                case "${event}" in
                    'ACCESS'|'CLOSE_NOWRITE'|'OPEN') #Non events
                        debug 8 "Non mutable event on: ${dir_file_events[0:1]} ${event}, ignoring"
                    ;;
                    'MODIFY'|'CLOSE_WRITE') # File modified events
                        debug 6 "File modification event on: ${dir_file_events[0:1]} ${event}"
                        if [ -n "${process}" ] ; then
                            killall -${signal} ${process}
                        fi
                    ;;
                    'MOVED_TO'|'CREATE') # New file events
                        debug 6 "New file event on: ${dir_file_events[0:1]} ${event}"
                        create_directory_structure "${destination}" "${dir_file_events[0]}" "${path}"
                        setup_named_pipe "${destination}" "${dir_file_events[0]}/${dir_file_events[1]}" "${path}" &
                    ;;
                    'MOVED_FROM'|'DELETE') # File/Directory deletion events
                        rm -f  
                        stop existing process and remove named pipe
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


function inotifywait {
    echo "${@}"
}


inotifywait -mr --timefmt '%d/%m/%y %H:%M' --format '%T %w %f' -e close_write /tmp/test | while read -r date time dir file; do
    #envsubst <"${file}"
    #mkfifo

     color_echo red "${date}"
     color_echo blue "${time}"
     color_echo cyan "${dir}"
     color_echo magenta "${file}"
     color_echo yellow "${start_timestamp}"
done
