#!/bin/bash
# shellcheck disable=SC2034,SC2174,SC2016,SC2026,SC2206,SC2128
#
# This is a collection of shared functions used by SD Elements products
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
#

# If there is no TTY then it's not interactive
if ! [[ -t 1 ]]; then
    interactive=false
fi
# Default is interactive mode unless already set
interactive="${interactive:-true}"

# Create which -s alias (whichs), same as POSIX: -s
# No output, just return 0 if all of the executables are found, or 1 if some were not found.
function whichs {
    command -v "${*}" >> /dev/null
}

# Set strict mode only for non-interactive (see bash tab completion bug):
# https://github.com/scop/bash-completion/issues/44
# https://bugzilla.redhat.com/show_bug.cgi?id=1055784
if ! ${interactive} ; then
    set -euo pipefail
fi

# Set Version
shtdlib_version='0.1'

# Timestamp, the date/time we started
start_timestamp=$(date +"%Y%m%d%H%M")

# Store original arguments/parameters
#base_arguments="${@:-}"

# Store original tty
init_tty="$(tty || true)"

# Determine OS family and OS type
OS="${OS:-}"
os_family='Unknown'
os_name='Unknown'
apt-get help > /dev/null 2>&1 && os_family='Debian'
yum help help > /dev/null 2>&1 && os_family='RedHat'
echo "${OSTYPE}" | grep -q 'darwin' && os_family='MacOSX'
if [ "${OS}" == 'SunOS' ]; then os_family='Solaris'; fi
if [ "${OSTYPE}" == 'cygwin' ]; then os_family='Cygwin'; fi
os_type="$(uname)"

# Determine virtualization platform in a way that ignores SIGPIPE, requires root
if [ "${EUID}" == 0 ] && command -v virt-what &> /dev/null ; then
    virt_platform="$(virt-what | head -1 || if [[ ${?} -eq 141 ]]; then true; else exit ${?}; fi)"
else
    virt_platform="Unknown"
fi

# Set major and minor version variables
if [ "${os_family}" == 'RedHat' ]; then
    major_version="$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | awk -F. '{print $1}')"
    minor_version="$(grep -oE '[0-9]+\.[0-9]+' /etc/redhat-release | awk -F. '{print $2}')"
    if ! [[ ${major_version} =~ ^-?[0-9]+$ ]] ; then # If major version is not an integer
        major_version="$(rpm -qa \*-release | grep -Ei 'oracle|redhat|centos' | cut -d'-' -f3)"
    fi
    if ! [[ ${minor_version} =~ ^-?[0-9]+$ ]] ; then # If minor version is not an integer
        minor_version="$(rpm -qa \*-release | grep -Ei 'oracle|redhat|centos' | cut -d'-' -f4 | cut -d'.' -f1)"
    fi

    # The following is a more robust way of determining the OS name than
    # `rpm-qa \*release | grep -q -Ei "^(redhat|centos)"`
    if grep -qEi 'centos' /etc/redhat-release; then
        os_name='centos';
    elif grep -qEi 'red ?hat' /etc/redhat-release; then
        os_name='redhat';
    fi
elif [ "${os_family}" == 'Debian' ]; then
    if [ -e '/etc/lsb-release' ] ; then
        major_version="$(grep DISTRIB_RELEASE /etc/lsb-release | awk -F= '{print $2}' | awk -F. '{print $1}')"
        minor_version="$(grep DISTRIB_RELEASE /etc/lsb-release | awk -F= '{print $2}' | awk -F. '{print $2}')"
        os_name="$(grep DISTRIB_ID /etc/lsb-release | awk -F= '{print $2}')"
    else
        major_version="$(awk -F. '{print $1}' /etc/debian_version)"
        minor_version="$(awk -F. '{print $2}' /etc/debian_version)"
        os_name='debian'
    fi
fi

# Store local IP addresses (not localhost)
local_ip_addresses="$( ( (whichs ip && ip -4 addr show) || (whichs ifconfig && ifconfig) || awk '/32 host/ { print "inet " f } {f=$2}' <<< \"$(</proc/net/fib_trie)\") | grep -v 127. | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*' | sort -u)"

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

# Check if a variable is in array
# First parameter is the variable, rest is the array
function in_array {
    local x
    for x in "${@:2}"; do [[ "${x}" == "${1}" ]] && return 0; done
    return 1
}

############################# Deprecated #######################################
############## Use variable=${variable:-value} instead  ########################
# Takes a variable name and sets it to the second parameter
# if it's not already been set use debug if it's available
function init_variable {
    debug 9 "init_variable is deprecated, use variable=${variable:-value} instead"
    # shellcheck disable=SC2086
    export $1=${!1:-${2:-}}
}

# Default verbosity, common levels are 0,1,5,10
verbosity="${verbosity:-1}"

# Colored echo
# takes color and message(s) as parameters, valid colors are listed in the constants section
function color_echo {
    printf "${!1}%s${blank}\\n" "${*:2}"
}

# Debug method for verbose debugging
# Note debug is special because it's safe even in subshells because it bypasses
# the stdin/stdout and writes directly to the terminal
function debug {
    if [ "${verbosity}" -ge "${1}" ]; then
        if [ -e "${init_tty}" ] ; then
            color_echo yellow "${*:2}" > "${init_tty}"
        else
            color_echo yellow "${*:2}"
        fi
    fi
}

# A platform (readlink implementation) neutral way to follow symlinks
function readlink_m {
    debug 10 "readlink_m called with: ${*}"
    args=( ${@} )
    if [ "${#args[@]}" -gt 1 ] ; then
        base_path="$(dirname "${args[0]}")"
        new_path="${base_path}/${args[1]}"
    else
        new_path="$(stat -f "%N %Y" "${args[0]}")"
    fi
    new_path=( ${new_path} )
    debug 10 "Processed path is: ${new_path[*]}"
    if [ ${#new_path[@]} -gt 1 ] || [ -L "${new_path[0]}" ] ; then
        readlink_m "${new_path[@]}"
    elif [ -e "${new_path[0]}" ] ; then
        echo "${new_path[0]}"
        return 0
    elif command -v realpath ; then
        realpath "${args[0]}"
        return 0
    else
        debug 10 "Failed to resolve path: ${new_path[*]}"
        return 1
    fi
}

# Returns the index number of the first version, in effect this means it
# returns true if the first value is the smallest
# and same number as versions if the first value is the largest.
# Example:
# compare_versions '1.1.1 1.2.2test' -> returns 0 # True
# compare_versions '1.2.2 1.1.1' -> returns 1 # False
# compare_versions '1.0.0 1.1.1 2.2.2' -> returns 0 # True
# compare_versions '4.0.0 3.0.0 2.0.0 1.1.1test 1.0.0' -> returns 4 # False but
# also position
function compare_versions {
    versions=(${@})
    return "$(($(printf "%s\\n" "${versions[@]}" | sort --version-sort | grep "${versions[0]}" --line-number | awk -F: '{print $1}')-1))"
}

# Converts relative paths to full paths, ignores invalid paths
# Accepts either the path or name of a variable holding the path
function finalize_path {
    local setvar
    # Check if there is a filesystem object matching the path
    if [ -e "${1}" ] || [[ "${1}" =~ '/' ]] || [[ "${1}" =~ '~' ]]; then
        path="${1}"
        setvar=false
    else
        debug 5 "Finalizing path for: ${1}"
        declare path="${!1}"
        setvar=true
    fi
    if [ -n "${path}" ] && [ -e "${path}" ] ; then
        if [ "${os_family}" == 'MacOSX' ] ; then
            full_path=$(readlink_m "${path}")
        else
            full_path="$(readlink -m "${path}")"
        fi
        debug 10 "Finalized path: '${path}' to full path: '${full_path}'"
        if [ -n "${full_path}" ]; then
            if ${setvar} ; then
                export "$1"="${full_path}"
            else
                echo "${full_path}"
            fi
        fi
    else
        debug 5 "Unable to finalize path: ${path}"
    fi
}

# Store full path to this script
script_full_path="${0}"
if [ ! -f "${script_full_path}" ] ; then
    script_full_path="$(pwd)"
fi

finalize_path script_full_path
run_dir="${run_dir:-$(dirname "${script_full_path}")}"

# Allows clear assert syntax
function assert {
  debug 10 "Assertion made: ${*}"
  # shellcheck disable=SC2068
  if ! "${@}" ; then
    color_echo red "Assertion failed: '${*}'"
    exit_on_fail
  fi
}

# Default is to clean up after ourselves
cleanup="${cleanup:-true}"

# Set username not available (unattended run)
if [ -z "${USER:-}" ]; then
    USER="$(whoami)"
    export USER
fi

# Set home directory if not available (unattended run)
if [ -z "${HOME:-}" ]; then
    HOME="$(getent passwd "${USER}" | awk -F: '{print $6}')"
    export HOME
fi

# Find the best way to escalate our privileges
function set_priv_esc_cmd {
    if [ "${EUID}" != "0" ]; then
        if [ -x "$(command -v sudo)" ]; then
            priv_esc_cmd='sudo -E'
        elif [ -x "$(command -v su)" ]; then
            priv_esc_cmd='su -c'
        else
            color_echo red "Not running as root and unable to locate/run sudo or su for privilege escalation"
            return 1
        fi
    else
        priv_esc_cmd=''
    fi
    return 0
}
set_priv_esc_cmd

# Magical sudo/su which preserves all ssh keys, kerb creds and def. ssh user
# and tty/pty
function priv_esc_with_env {
    debug 10 "Calling: \"${priv_esc_cmd} ${*}\" on tty: \"${init_tty}\" with priv esc command as: \"${priv_esc_cmd}\" and user: \"${USER}\""
    debug 11  "${priv_esc_cmd} /bin/bash -c export SSH_AUTH_SOCK='${SSH_AUTH_SOCK}' && export SUDO_USER_HOME='${HOME}' && export KRB5CCNAME='${KRB5CCNAME}' && export GPG_TTY='${init_tty}' && alias ssh='ssh -l ${USER}' && ${*}"
    ${priv_esc_cmd} /bin/bash -c "export SSH_AUTH_SOCK='${SSH_AUTH_SOCK}' && export SUDO_USER_HOME='${HOME}' && export KRB5CCNAME='${KRB5CCNAME}' && export GPG_TTY='${init_tty}' && alias ssh='ssh -l ${USER}' && ${*}"
    return ${?}
}

# A subprocess which performs a command when it receives a signal
# First parameter is the signal and the rest is assumed to be the command
# Returns the PID of the subprocess
function signal_processor {
    local signal="${1}"
    local command="${*:2}"
    bash -c "trap '${command}' ${signal} && while true; do sleep 1 ; done" &> /dev/null &
    echo "${!}"
}

# Signals a process by either exact name or pid
# Accepts name/pid as first parameter and optionally signal as second parameter
function signal_process {
debug 8 "Signaling ${1} with ${2:-SIGTERM}"
if [[ "${1}" =~ ^[0-9]+$ ]] ; then
    if [ "${2}" != '' ] ; then
        kill -s "${2}" "${1}"
    else
        kill "${1}"
    fi
else
    if [ "${2}" != '' ] ; then
        pkill --exact --signal "${2}" "${1}"
    else
        pkill --exact "${1}"
    fi
fi
}

# Allows checking of exit status, on error print debugging info and exit.
# Takes an optional error message in which case only it will be shown
# This is typically only used when running in non-strict mode but when errors
# should be raised and to help with debugging
function exit_on_fail {
    message="${*:-}"
    if [ -z "${message}" ] ; then
        color_echo red "Last command did not execute successfully but is required!" >&2
    else
        color_echo red "${*}" >&2
    fi
    debug 10 "[$( caller )] ${*}"
    debug 10 "BASH_SOURCE: ${BASH_SOURCE[*]}"
    debug 10 "BASH_LINENO: ${BASH_LINENO[*]}"
    debug 0  "FUNCNAME: ${FUNCNAME[*]}"
    # Exit if we are running as a script
    if [ -f "${script_full_path}" ]; then
        exit 1
    fi
}

# Traps for cleaning up on exit
# Note that trap definition needs to happen here not inside the add_on_sig as
# shown in the original since this can easily be called in a subshell in which
# case the trap will only apply to that subshell
declare -a on_exit
declare -a on_break

function on_exit {
    # shellcheck disable=SC2181
    if [ ${?} -ne 0 ]; then
        # Prints to stderr to provide an easy way to check if the script
        # failed. Because the exit signal gets propagated only the first call to
        # this function will know the exit code of the script. All subsequent
        # calls will see $? = 0 if the previous signal handler did not fail
        color_echo red "Last command did not complete successfully" >&2
    fi

    if [ -n "${on_exit:-}" ] ; then
        debug 10 "Received SIGEXIT, ${#on_exit[@]} items to clean up."
        if [ ${#on_exit[@]} -gt 0 ]; then
            for item in "${on_exit[@]}"; do
                if [ -n "${item}" ] ; then
                    debug 10 "Executing cleanup statement on exit: ${item}"
                    # shellcheck disable=SC2091
                    ${item}
                fi
            done
        fi
    fi
    debug 10 "Finished cleaning up, de-registering signal trap"
    # Be a nice Unix citizen and propagate the signal
    trap - EXIT
    kill -s EXIT ${$}
}

function on_break {
    if [ -n "${on_break:-}" ] ; then
        color_echo red "Break signal received, unexpected exit, ${#on_break[@]} items to clean up."
        if [ ${#on_break[@]} -gt 0 ]; then
            for item in "${on_break[@]}"; do
                if [ -n "${item}" ] ; then
                    color_echo red "Executing cleanup statement on break: ${item}"
                    ${item}
                fi
            done
        fi
    fi
    # Be a nice Unix citizen and propagate the signal
    trap - "${1}"
    kill -s "${1}" "${$}"
}

function add_on_exit {
    debug 10 "Registering signal action on exit: \"${*}\""
    local n=${#on_exit[*]}
    on_exit[${n}]="${*}"
    debug 10 "on_exit content: ${on_exit[*]}, size: ${#on_exit[*]}, keys: ${!on_exit[*]}"
}

function add_on_break {
    debug 10 "Registering signal action on break: \"${*}\""
    local n=${#on_break[*]}
    on_break[${n}]="${*}"
    debug 10 "on_break content: ${on_break[*]}, size: ${#on_break[*]}, keys: ${!on_break[*]}"
}

function add_on_sig {
    add_on_exit "${*}"
    add_on_break "${*}"
}

function clear_sig_registry {
    debug 10 "Clearing all registered signal actions"
    on_exit=()
    on_break=()
}

debug 10 "Setting up signal traps"
trap on_exit EXIT
trap "on_break INT" INT
trap "on_break QUIT" QUIT
trap "on_break TERM" TERM
debug 10 "Signal trap successfully initialized"

# Creates a secure temporary directory or file
#   First argument (REQUIRED) is the name of the caller's return variable
#   Second argument (REQUIRED) is either 'dir' or 'file'
#   Third argument (OPTIONAL) can either be an existing or non-existing directory
#
# If "file" is chosen and the second argument matches a dir a tmp file with a
# random filename will be created.
# If "dir" is chosen and the second argument matches a dir a tmp dir with a
# random name will be created.
# If "file" is chosen and the second argument does not match any existing
# directory a temporary file with that name will be created.
# If "dir" is chosen and the second argument does not match any existing
# directory a temporary dir with that name will be created.
# If no second argument is given a randomly named tmp file/dir will be created
#
# DO NOT call this function in a subshell, it breaks the clean up functionality.
# Instead, call the function with the name of the caller's return variable as the
# first argument. For example:
#    local my_temp_dir=""
#    create_secure_tmp my_temp_dir 'dir'
function create_secure_tmp {
    # Check for the minimum number of arguments
    if [ ${#@} -lt 2 ]; then
        color_echo red "Called 'create_secure_tmp' with less than 2 arguments."
        exit_on_fail
    fi

    # Save the name of the caller's return variable
    local _RETVAL=${1}

    local type_flag
    if [ "${2}" == 'file' ] ; then
        type_flag=''
    elif [ "${2}" == 'dir' ] ; then
        type_flag='-d'
    else
        color_echo red 'Called create_secure_tmp without specifying a required second argument "dir" or "file"!'
        color_echo red "You specified: ${2}"
        exit_on_fail
    fi
    original_umask="$(umask)"
    umask 0007

    # Should not be a local variable so the calling environment can access it
    secure_tmp_object=""
    dir=${3:-}
    if [ -d "${dir}" ]; then
        if [ "${os_type}" == 'Linux' ]; then
            secure_tmp_object="$(mktemp ${type_flag} --tmpdir="${dir}" -q )"
        else
            TMPDIR="${3}"
            secure_tmp_object="$(mktemp -t tmp -q)"
        fi
    elif [ -e "${dir}" ] || [ -z "${dir}" ]; then
        if [  "${os_type}"  == 'Linux' ]; then
            secure_tmp_object="$(mktemp ${type_flag} -q)"
        else
            secure_tmp_object="$(mktemp ${type_flag} -q -t tmp)"
        fi
    else
        if [ "${2}" == 'file' ] ; then
            mkdir -p -m 0700 "$(dirname "${dir}")" || exit_on_fail
            install -m 0600 /dev/null "${dir}" || exit_on_fail
        elif [ "${2}" == 'dir' ] ; then
            mkdir -p -m 0700 "${dir}" || exit_on_fail
        fi
        secure_tmp_object="${dir}"
    fi
    # shellcheck disable=SC2181
    if [ ${?} -ne 0 ]; then
        exit_on_fail "${secure_tmp_object}"
    fi
    chmod 0700 "${secure_tmp_object}" || exit_on_fail
    umask "${original_umask}" || exit_on_fail

    # Store temp file/dir path into the caller's variable
    # shellcheck disable=SC2086
    eval ${_RETVAL}="'$secure_tmp_object'"

    if ${cleanup}; then
        debug 10 "Setting up signal handler to delete tmp object ${secure_tmp_object} on exit"
        add_on_sig "rm -Rf ${secure_tmp_object}"
    fi
}

# Extracts archives
# First argument is the archive, second is the destination folder
# Any subsequent arguments are assumed to be embedded archives to try to
# extract, these will all be normalized into the dest folder
# If no arguments are given or a simple dash it's assumed the archive is
# provided on stdin in which case we try to determine the type and extract
# using a temporary file
# Examples of usage:
# stdin/stdout:       extract < cat /some/file OR  cat /some/file | extract
# stdin/filename:     extract - /output/path
# filename/filename:  extract /input/path /output/path
# filename/stdout:    extract /input/path
declare -a extract_trailing_arguments
function extract {
    # Check if we have a filename or are dealing with data on stdin
    if [ "${1:-}" == '-' ] || [ "${1:-}" == '' ] ; then
        if [ "${2:-}" != '' ] ; then
            dest_flag_place="-C ${2}"
        else
            dest_flag_place=''
        fi
        tmp_archive="$(mktemp)"
        case "$(tee "${tmp_archive}" &> /dev/null && file "${tmp_archive}" --brief --mime-type)" in
            application/x-tar)  tar xf "${tmp_archive}" ${dest_flag_place};;
            application/x-gzip) tar zxf "${tmp_archive}" ${dest_flag_place};;
            application/pgp)    gpg -q -o - --decrypt "${tmp_archive}" | extract "${@:1}";;
            *) color_echo red "Unsupported mime type for extracting file from stdin" ;;
        esac
        debug 10 "Removing temporary archive: ${tmp_archive}"
        rm -f "${tmp_archive}"
    else
        if [ "${verbosity}" -ge 10 ]; then
            local tar_verb_flag="--verbose"
        else
            local tar_verb_flag=''
        fi
        if [ -f "${1}" ] && [ -d "${2}" ]; then
            case "${1}" in
                *.tar.bz2)   ${priv_esc_cmd} tar xvjf      "${1}" -C "${2}"   ${tar_verb_flag};;
                *.tar.gz)    ${priv_esc_cmd} tar xvzf      "${1}" -C "${2}"   ${tar_verb_flag};;
                *.bz2)       ${priv_esc_cmd} bunzip2 -dc   "${1}" > "${2}"   ;;
                *.rar)       ${priv_esc_cmd} unrar x       "${1}" "${2}"     ;;
                *.gz)        ${priv_esc_cmd} gunzip -c     "${1}" > "${2}"   ;;
                *.tar)       ${priv_esc_cmd} tar xvf       "${1}" -C "${2}"   ${tar_verb_flag};;
                *.pyball)    ${priv_esc_cmd} tar xvf       "${1}" -C "${2}"   ${tar_verb_flag};;
                *.tbz2)      ${priv_esc_cmd} tar xvjf      "${1}" -C "${2}"   ${tar_verb_flag};;
                *.tgz)       ${priv_esc_cmd} tar xvzf      "${1}" -C "${2}"   ${tar_verb_flag};;
                *.zip)       ${priv_esc_cmd} unzip         "${1}" -d "${2}"  ;;
                *.Z)         ${priv_esc_cmd} uncompress -c "${1}" > "${2}"   ;;
                *.7z)        ${priv_esc_cmd} 7za x -y      "${1}" -o"${2}" ;;
                *.tar.gpg)   ${priv_esc_cmd} gpg -q -o - --decrypt "${1}" | tar xv -C "${2}" ${tar_verb_flag};;
                *.tgz.gpg)   ${priv_esc_cmd} gpg -q -o - --decrypt "${1}" | tar xvz -C "${2}" ${tar_verb_flag};;
                *.tar.gz.gpg)   ${priv_esc_cmd}gpg -q -o - --decrypt "${1}" | tar xvz -C "${2}" ${tar_verb_flag};;
                *)           color_echo red "${1} is not a known compression format" ;;
            esac
            extract_trailing_arguments=("${@:3}:-")
            if [ -n "${extract_trailing_arguments}" ] ; then
                if [ -f "${2}"/"${extract_trailing_arguments}" ] ; then
                    extract "$(find "${2}/${extract_trailing_arguments}")" "${2}"
                    extract_trailing_arguments=("${extract_trailing_arguments[@]:1}")
                fi
            else
                color_echo cyan "Did not find any embedded archive matching ${extract_trailing_arguments}"
            fi
        else
            color_echo red "'${1}' is not a valid file or '${2}' is not a valid directory"
            exit_on_fail
        fi
    fi
}

# If script is a part of a self extracting executable tar archive
# Extract itself and set variable to path
function extract_exec_archive {
    # create_secure_tmp will store return data into the first argument
    create_secure_tmp tmp_archive_dir 'dir'
    export tmp_archive_dir
    if ${interactive} ; then
        while ! [[ "${REPLY:-}" =~ ^[NnYy]$ ]]; do
            color_echo magenta "Detected self extracting executable archive"
            read -rp "Please confirm you want to continue and extract the archive (Yy/Nn): " -n 1
            echo ""
        done
    else
        REPLY="y"
    fi
    if [[ ${REPLY} =~ ^[Yy]$ ]]; then
        bash_num_lines="$(awk '/^__ARCHIVE_FOLLOWS__/ { print NR + 1; exit 0; }' "${script_full_path}")"
        debug 10 "Extracting embedded tar archive to ${tmp_archive_dir}"
        tail -n +"${bash_num_lines}" "${script_full_path}" | extract - "${tmp_archive_dir}" || exit_on_fail
    else
        color_echo red "Archive extraction cancelled by user!"
        exit -1
    fi
}

# If this script is being run as a part of an executable installer archive handle correctly
if [ -f "${script_full_path}" ] && grep -qe '^__ARCHIVE_FOLLOWS__' "${script_full_path}" ; then
    export running_as_exec_archive=true
    debug 5 "Detected I'm an executable archive"
    extract_exec_archive
    if [ "$(type -t run_if_exec_archive)" == 'function' ] ; then
        debug 10 "Found function named run_if_exec_archive, running it!"
        run_if_exec_archive
    else
        debug 10 "Did not find a function named run_if_exec_archive, continuing"
    fi
else
    debug 5 "Detected I'm running as a script or interactive"
    running_as_exec_archive=false
fi

# This is a sample print usage function, it should be overwritten by scripts
# which import this library
function print_usage {
cat << EOF
usage: ${0} options

This is an example usage help function

OPTIONS:
   -x      Create an example bundle, optionally accepts a release, defaults to acme release
   -a      Apply an example bundle
   -s      Sign a bundle being created and force validation when it's applied
   -p      Create a patch, the patch only includes acme updates and does not update the release
   -h      Show this message
   -v      Print ${0} version and exit

Examples:
${0} -c # Create a bundle with "acme"  version
${0} -sc 1.0.1 # Create and sign an acme bundle with version 1.0.1
${0} -a # Apply example update, default action when run from archive

Version: ${version:-${shtdlib_version}}
EOF
}

# Exits with error if a required argument was not provided
# Takes two arguments, first is the argument value and the second
# is the error message if argument is not set
# This is mostly irrelevant when running in strict mode
function required_argument {
    print_usage_function="${3:-print_usage}"
    if [ -z "${!1}" ]; then
        ${print_usage_function}
        color_echo red "${2}"
        exit -1
    fi
}

# Sometimes we want to process the required arguments later
declare -a arg_var_names
declare -a arg_err_msgs
function deferred_required_argument {
    arg_var_names+=("${1}")
    arg_err_msgs+=("${2}")
}
function process_deferred_required_arguments {
    for ((i=0;i<${#arg_var_names[@]};++i)) ; do
        required_argument "${arg_var_names[$i]}" "${arg_err_msgs[$i]}"
    done
}

# Parse for optional arguments (-f vs. -f optional_argument)
# Takes variable name as first arg and default value as optional second
# variable will be initialized in any case for compat with -e
parameter_array=(${@}) # Store all parameters as an array
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

# Resolve DNS name, returns IP if successful, otherwise name and error code
function resolve_domain_name {
    lookup_result="$( (whichs getent && getent ahosts "${1}" | awk '{ print $1 }'| sort -u) || (whichs dscacheutil && dscacheutil -q host -a name "${1}" | grep ip_address | awk '{ print $2 }'| sort -u ))"
    if [ -z "${lookup_result}" ]; then
        echo "${1}"
        return 1
    else
        echo "${lookup_result}"
        return 0
    fi
}

# Resolve DNS SRV name given a service and a domain, returns host name(s)
function resolve_srv_name {
    service="_${1}"
    domain="${2}"
    proto="_${3:-TCP}"
    debug 10 "${service} ${domain} ${proto}"
    mapfile -t lookup_result <<< "$(host -t SRV "${service}.${proto}.${domain}" ; echo -e "${?}" )"
    if test "${lookup_result[@]: -1}" -eq 0 ; then
        for line in "${lookup_result[@]}"; do
            echo "${line}"
        done
    else
        debug 2 "Failed to resolve ${service} ${domain} ${proto}"
    fi
}

# Wait for file to exists
#  - first param: filename,
#  - second param: timeout (optional, default 5 sec)
#  - third param: sleep interval (optional, default 1 sec)
function wait_for_file {
    local file_name="${1}"
    local timeout="${2:-5}"
    local sleep_interval="${3:-1}"
    local max_count=$((timeout/sleep_interval))
    local count=0
    while [ ! -f "${file_name}" ]; do
        (( count++ ))
        if [ ${count} -ge ${max_count} ]; then
            break
        else
            sleep "${sleep_interval}"
        fi
    done
}

# Wait for a command to return a 0 exit status
#  - first param: command
#  - second param: timeout (optional, default 10 sec)
#  - third param: sleep interval (optional, default 1 sec)
function wait_for_success {
    local command="${1:-false}"
    local timeout="${2:-10}"
    local sleep_interval="${3:-1}"
    local max_count=$((timeout/sleep_interval))
    local count=0
    while ! ${command}; do
        (( count++ ))
        if [ ${count} -ge ${max_count} ]; then
            return 1
        else
            sleep "${sleep_interval}"
        fi
    done
}

# Helper function for copy_file
# Sets Permission/Owner on files
# Takes params/args file, owner[:group], oct_mode (permission)
function set_file_perm_owner {
    debug 10 "Called set_file_perm_owner with ${1}, ${2}, ${3}"
    if [ -z "${2}" ] ; then
        rsync_base_flags="${rsync_base_flags} -og"
    else
        debug 10 "Changing owner on ${1} to ${2}"
        rsync_base_flags="${rsync_base_flags} --usermap=${2}"
        # Workaround when running from setuid and no supplemental groups are
        # loaded automatically
        # shellcheck disable=SC2091
        if [ "${EUID}" -ne '0' ] && $(echo "${2}" | grep -q ':') ; then
            group="$(echo "${user_group:-}" | awk -F: '{print $2}')"
            if [[ "${group}" != '' ]]; then
                sg "${group}" -c "chown '${2}' '${1}'" || exit_on_fail
            fi
        else
            chown "${2}" "${1}" || exit_on_fail
        fi
    fi
    if [ -z "${3}" ] ; then
        rsync_base_flags="${rsync_base_flags} -p"
    else
        debug 10 "Changing permissions on ${1} to ${3}"
        rsync_base_flags="${rsync_base_flags} --chmod=${3}"
        chmod "${3}" "${1}" || exit_on_fail
    fi
}

# Helper function for copy_dir
# Sets Permission/Owner of directories
# Takes params/args directory, owner[:group], oct_mode, file permission
function set_dir_perm_owner {
    debug 10 "Called set_dir_perm_owner with ${1}, ${2}, ${3}, ${4}"
    if [ -z "${2}" ] ; then
        rsync_base_flags="${rsync_base_flags} -og"
    else
        debug 10 "Changing owner on ${1} to ${2}"
        rsync_base_flags="${rsync_base_flags} --usermap=${2}"
        # Workaround when running from setuid and no supplemental groups are
        # loaded automatically
        # shellcheck disable=SC2091
        if [ "${EUID}" -ne '0' ] && $(echo "${2}" | grep -q ':') ; then
            group="$(echo "${user_group:-}" | awk -F: '{print $2}')"
            if [[ "${group}" != '' ]]; then
                sg "${group}" -c "chown '${2}' ${1}" || exit_on_fail
            fi
        else
            chown -R "${2}" "${1}" || exit_on_fail
        fi
    fi
    if [ -z "${3}" ] ; then
        rsync_base_flags="${rsync_base_flags} -p"
    else
        debug 10 "Changing permissions recursively on dirs in ${1} to ${3}"
        rsync_base_flags="${rsync_base_flags} --chmod=${3}"
        find "${1}" -type d -exec chmod "${3}" {} +
    fi
    if [ -n "${4}" ] ; then
        debug 10 "Changing permissions recursively on files in ${1} to ${4}"
        # Figure out how to do this with rsync
        #rsync_base_flags="${rsync_base_flags} --chmod=${4}"
        find "${1}" -type f -exec chmod "${4}" {} +
    fi
}

# Very cautiously copy files
# First parameter source, second destination, third owner:group, fourth
# permissions, until we have rsync 3.1 everywhere we are actually changing
# the permissions on the source files which is not an issue when it's a tmp dir
# but could be an issue if used in a different way. Third and fourth parameters
# are optional
function copy_file {
    rsync_base_flags="-ltDu  --inplace --backup --backup-dir=\"${backup_dir:-${dest}.backup}\" --keep-dirlinks"
    local source="${1}"
    local dest="${2}"
    local owner_group="${3:-}"
    local perm="${4:-}"
    set -f
    find_directory="$(dirname "${source}")"
    find_pattern="$(basename "${source}")"
    set +f
    debug 10 "Called copy_file with ${source} ${dest} ${owner_group} ${perm}"
    # shellcheck disable=SC2086
    if [ -e "${source}" ] ; then
        debug 10 "Filesystem object ${source} exists"
        # Make sure permissions and owner are OK
        set_file_perm_owner "${source}" "${owner_group}" "${perm}"
        if [ -f "${source}" ] ; then
            debug 10 "Found file ${source}"
            if "${force_overwrite:-false}" ; then
                debug 10 "Copying with forced overwrite"
                rsync_flags="${rsync_base_flags} --force"
                #rsync ${rsync_flags} "${1}" "${2}"
                cp -pf "${source}" "${dest}" || exit_on_fail
            elif "${interactive}" ; then
                debug 10 "Copying in interactive mode"
                rsync_flags="${rsync_base_flags}"
                #rsync ${rsync_flags} "${1}" "${2}"
                cp -pi "${source}" "${dest}" || exit_on_fail
            else
                debug 10 "Copying in non-interactive mode"
                flags="${rsync_base_flags}"
                #rsync ${rsync_flags} "${1}" "${2}"
                cp -pn "${source}" "${dest}" || exit_on_fail
            fi
            debug 10 "Copied file ${source} to ${dest}"
        else
            color_echo red "Found filesystem object ${source} but it's not a file"
            return 1
        fi
    # Support globbing
    elif [ -n "$(find ${find_directory} -maxdepth 1 -name ${find_pattern} -type f -print -quit)" ] ; then
        debug 10 "Found globbing pattern in ${1}"
        # Make sure permissions and owner are OK
        set_file_perm_owner "${source}" "${owner_group}" "${perm}"
        if "${force_overwrite:-false}" ; then
            debug 10 "Copying with forced overwrite"
            cp -pf ${source} "${dest}" || exit_on_fail
        elif "${interactive}" ; then
            debug 10 "Copying in interactive mode"
            cp -pi ${source} "${dest}" || exit_on_fail
        else
            debug 10 "Copying in non-interactive mode"
            cp -pn ${source} "${dest}" || exit_on_fail
        fi
        copied_files="$(find ${source} -type f -exec basename {} \; | tr '\n' ' ')"
        debug 10 "Copied file(s) ${copied_files} to ${dest}"
    else
        color_echo cyan "Unable to find filesystem object ${source} while looking for file. Skipping..."
        return 1
    fi
    return 0
}

# Very cautiously copy directories
# First parameter source, second destination, third owner:group, fourth dir
# permissions, fifth file permissions. Last three parameters are optional
function copy_dir {
    local source="${1}"
    local dest="${2}"
    local owner_group="${3:-}"
    local file_perm="${4:-}"
    local dir_perm="${5:-}"
    set -f
    find_directory="$(dirname "${source}")"
    find_pattern="$(basename "${source}")"
    set +f
    # shellcheck disable=SC2086
    if [ -e "${source}" ] ; then
        debug 10 "Filesystem object ${source} exists"
        set_dir_perm_owner "${source}" "${owner_group}" "${file_perm}" "${dir_perm}"
        if [ -d "${source}" ] ; then
            debug 10 "Found directory ${source}"
            if "${force_overwrite:-false}" ; then
                debug 10 "Copying with forced overwrite"
                cp -Rpf "${source}" "${dest}" || exit_on_fail
            elif "${interactive}" ; then
                debug 10 "Copying in interactive mode"
                cp -Rpi "${source}" "${dest}" || exit_on_fail
            else
                debug 10 "Copying in non-interactive mode"
                cp -Rpn "${source}" "${dest}" || exit_on_fail
            fi
            debug 10 "Copied dir ${source} to ${dest}"
        else
            color_echo red "Found filesystem object ${source} but it's not a directory"
            return 1
        fi
    # Support globbing
    elif [ -n "$(find ${find_directory} -maxdepth 1 -name ${find_pattern} -type f -print -quit)" ] ; then
        debug 10 "Found globbing pattern in ${source}"
        set_dir_perm_owner "${source}" "${owner_group}" "${file_perm}" "${dir_perm}"
        if "${force_overwrite:-false}" ; then
            debug 10 "Copying with forced overwrite"
            cp -Rpf ${source} "${dest}" || exit_on_fail
        elif "${interactive}" ; then
            debug 10 "Copying in interactive mode"
            cp -Rpi ${source} "${dest}" || exit_on_fail
        else
            debug 10 "Copying in non-interactive mode"
            cp -Rpn ${source} "${dest}" || exit_on_fail
        fi
        copied_dirs="$(find ${source} -type f -exec basename {} \; | tr '\n' ' ')"
        debug 10 "Copied dir(s) ${copied_dirs}"
    else
        color_echo cyan "Unable to find filesystem object ${source} while looking for dir"
        return 1
    fi
    return 0
}

# Create directories, first argument is path, second is owner, third is
# group, fourth is mode
function create_dir_or_fail {
    # Make sure directory exist, offer to create it or fail
    debug 10 "Asked to create/check directory ${1}"
    if [ ! -d "${1}" ]; then
        if [ -e "${1}" ]; then
            color_echo red "A non directory object already exists at ${1}"
            exit_on_fail
        fi
        # Offer to create the directory if it does not exist
        if ${interactive} ; then
            while ! [[ "${REPLY}" =~ ^[NnYy]$ ]]; do
                read -rp "The directory ${1} does not exist, do you want to create it (y/n):" -n 1
                echo ""
            done
        else
            REPLY="y"
        fi
        if [[ ${REPLY} =~ ^[Yy]$ ]]; then
            color_echo green "Creating directory ${1}"
            if [ "${4}" != "" ] ; then
                mode_flag="-m ${4}"
            else
                mode_flag=''
            fi
            # Create dir, use sudo/su if required
            if [ -w "$(dirname "${1}")" ] ; then
                mkdir -p "${1}" "${4}"
            else
                ${priv_esc_cmd} mkdir -p "${1}" "${4}"
            fi
            # Change owner if specified
            if  [ "${2}" != "" ] && [ "$(stat -c '%U' "${1}")" != "${2}" ] ; then
                debug 5 "Changing owner on ${1} to ${2}"
                ${priv_esc_cmd} chown "${2}" "${1}"
            fi
            # Change group if specified
            if  [ "${3}" != "" ] && [ "$(stat -c '%G' "${1}")" != "${3}" ] ; then
                debug 5 "Changing group on ${1} to ${3}"
                ${priv_esc_cmd} chgrp "${3}" "${1}"
            fi
        else
            color_echo red "Target directory is required"
            exit_on_fail
        fi
    fi
}

# Takes yaml file as first parameter and key as second, e.g.
# load_from_yaml /etc/custom.yaml puppet::mykey (additional keys can be follow)
# example load_from_yaml example.yaml ':sources' ':base' "'remote'"
function load_from_yaml {
    if [ -r "${1}" ]; then
        ruby_yaml_parser="data = YAML::load(STDIN.read); puts data['${2}']"
        for key in "${@:3}" ; do
            ruby_yaml_parser+="[${key}]"
        done
        set -o pipefail
        #debug 10 "Using the following Yaml parser ${ruby_yaml_parser}"
        ruby -w0 -ryaml -e "${ruby_yaml_parser}" "${1}" 2> /dev/null | awk '{print $1}' || return 1
        set +o pipefail
        return 0
    else
        return 1
    fi
}

# Install gem if not already installed
# Returns 0 if package was installed, 1 if package was already installed
function install_gem {
    original_umask="$(umask)"
    if [ "${verbosity}" -le 5 ]; then
        gem_verb_flag='-q'
    elif [ "${verbosity}" -ge 10 ]; then
        gem_verb_flag='-V'
    else
        gem_verb_flag=''
    fi
    # First try gem with version code, ala ubuntu or installed with gem but
    # default to basic gem command
    gem_cmd="$(compgen -c | grep '^gem[0-9][0-9]*\.*[0-9][0-9]*' | sort | tail -n1)"
    if [ "${gem_cmd}" == '' ]; then
        gem_cmd='gem'
    fi
    debug 10 "Using gem command: '${gem_cmd}'"
    gem_version=$(${gem_cmd} list "${1}" | grep -e "^${1}")
    debug 10 "Query for gem package '${1}' version returned: '${gem_version}'"
    if [ "${gem_version}" == "" ]; then
        umask 0002
        ${priv_esc_cmd} bash -c "${gem_cmd} install ${gem_verb_flag} ${1} ${2}" || exit_on_fail
        umask "${original_umask}" || exit_on_fail
        return 0
    fi
    return 1
}

function validate_hostfile {
    assigned_ip_addresses="$(ip -4 addr show | grep -Eo 'inet (addr:)?([0-9]*\.){3}[0-9]*' | grep -Eo '([0-9]*\.){3}[0-9]*')"
    ip_address_in_hostfile="$(getent hosts | grep -e "\\b$(hostname)\\b" | awk '{print $1}')"

    debug 10 "Currently assigned IP addresses: ${assigned_ip_addresses}"
    debug 10 "IP address associated with hostname on hostfile: ${ip_address_in_hostfile}"

    if echo "${assigned_ip_addresses}" | grep -q "${ip_address_in_hostfile}" ; then
        debug 8 "Hostname found in hostfile and resolves to IP address on the system"
    else
        color_echo red  "Unable to resolve hostname to any IP address on the system"
        exit_on_fail
    fi
}

# URI parsing function
#
# The function creates global variables with the parsed results.
# It returns 0 if parsing was successful or non-zero otherwise.
#
# [schema://][user[:password]@]host[:port][/path][?[arg1=val1]...][#fragment]
#
# Originally from: http://vpalos.com/537/uri-parsing-using-bash-built-in-features/
function uri_parser {
    # uri capture
    uri="${*}"

    # safe escaping
    uri="${uri//\`/%60}"
    uri="${uri//\"/%22}"

    # top level parsing
    pattern='^(([a-z]{3,5})://)?((([^:\/]+)(:([^@\/]*))?@)?([^:\/?]+)(:([0-9]+))?)([:\/][^?]*)?(\?[^#]*)?(#.*)?$'
    [[ "${uri}" =~ ${pattern} ]] || [[ "${uri}" =~ ssh://${pattern} ]]  || return 1;

    # component extraction
    uri=${BASH_REMATCH[0]}
    uri_schema=${BASH_REMATCH[2]}
    uri_address=${BASH_REMATCH[3]}
    uri_user=${BASH_REMATCH[5]}
    uri_password=${BASH_REMATCH[7]}
    uri_host=${BASH_REMATCH[8]}
    uri_port=${BASH_REMATCH[10]}
    uri_path=${BASH_REMATCH[11]}
    uri_query=${BASH_REMATCH[12]}
    uri_fragment=${BASH_REMATCH[13]}

    # path parsing
    local count
    count=0
    path="${uri_path}"
    pattern='^/+([^/]+)'
    while [[ ${path} =~ ${pattern} ]]; do
        eval "uri_parts[${count}]=\"${BASH_REMATCH[1]}\""
        path="${path:${#BASH_REMATCH[0]}}"
        (( count++ )) && true
    done
    # query parsing
    count=0
    query="${uri_query}"
    pattern='^[?&]+([^= ]+)(=([^&]*))?'
    while [[ ${query} =~ ${pattern} ]]; do
        eval "uri_args[${count}]=\"${BASH_REMATCH[1]}\""
        eval "uri_arg_${BASH_REMATCH[1]}=\"${BASH_REMATCH[3]}\""
        query="${query:${#BASH_REMATCH[0]}}"
        (( count++ )) && true
    done

    debug 8 "Uri parser paring summary:"
    debug 8 "uri_parser: uri          -> ${uri}"
    debug 8 "uri_parser: uri_schema   -> ${uri_schema}"
    debug 8 "uri_parser: uri_address  -> ${uri_address}"
    debug 8 "uri_parser: uri_user     -> ${uri_user}"
    debug 8 "uri_parser: uri_password -> ${uri_password}"
    debug 8 "uri_parser: uri_host     -> ${uri_host}"
    debug 8 "uri_parser: uri_port     -> ${uri_port}"
    debug 8 "uri_parser: uri_path     -> ${uri_path}"
    debug 8 "uri_parser: uri_query    -> ${uri_query}"
    debug 8 "uri_parser: uri_fragment -> ${uri_fragment}"

    # return success
    return 0
}

## Create a uri back from all the variables created by uri_parser
# [schema://][user[:password]@]host[:port][/path][?[arg1=val1]...][#fragment]
function uri_unparser {
    working_uri="${uri_schema}://"
    if [ -n "${uri_user}" ] && [ -n "${uri_password}" ] ; then
        working_uri+="${uri_user}:${uri_password}@"
    fi
    working_uri+="${uri_host}"
    if [ -n "${uri_port}" ] ; then
        working_uri+=":${uri_port}"
    fi
    if [ -n "${uri_path}" ] ; then
        working_uri+="${uri_path}"
    fi
    if [ -n "${uri_query}" ] ; then
        working_uri+="?${uri_query}"
    fi
    if [ -n "${uri_fragment}" ] ; then
        working_uri+="#${uri_fragment}"
    fi
    echo "${working_uri}"
}

## Strip all leading/trailing whitespaces
function strip_space {
    echo -n "${@}" | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//'
}

# Usage
# This function is used to safely edit files for config parameters, etc
# This function will return 0 on success or 1 if it fails to change the value
#
# OPTIONS:
#   -n      Filename, for example: /tmp/config_file
#   -p      Regex pattern, for example: ^[a-z]*
#   -v      Value, the value to replace with, can include variables from previous regex
#           pattern, if omitted the pattern is used as the value
#   -a      Append, if this flag is specified and the pattern does not exist it will be
#           created, takes an optional argument which is the [INI] section to add the pattern to
#   -o      Opportunistic, don't fail if pattern is not found, takes an optional argument
#           which is the number of matches expected/required for the change to be performed
#   -c      Create, if file does not exist we create it, assumes append and opportunistic
function safe_find_replace {
local OPTIND OPTARG opt filename pattern new_value force opportunistic create append ini_section req_matches n p v a o c
    filename=""
    pattern=""
    new_value=""
    force=false
    opportunistic=false
    create=false
    append=false
    ini_section=""
    req_matches=1

    # Handle arguments
    while getopts "n:p:v:aoc" opt; do
        case ${opt} in
            'n')
                filename="${OPTARG}"
            ;;
            'p')
                # Properly escape control characters in pattern
                pattern="$(echo "${OPTARG}" | sed -e 's/[\/&]/\\\\&/g')"
                debug 10 "Pattern set to ${pattern}"

                # If value is not set we set it to pattern for now
                if [ "${new_value}" == "" ]; then
                    new_value="${pattern}"
                fi
            ;;
            'v')
                # Properly escape control characters in new value
                new_value="$(echo "${OPTARG}" | sed -e 's/[\/&]/\\\\&/g')"
            ;;
            'a')
                append=true
                parse_opt_arg ini_section
            ;;
            'o')
                opportunistic=true
                parse_opt_arg req_matches
            ;;
            'c')
                create=true
                append=true
                opportunistic=true
            ;;
            *)
                print_usage
        esac
    done
    # Cleanup getopts variables
    unset OPTSTRING OPTIND

    # Make sure all required parameters are provided
    if [ "${filename}" == "" ] || [ "${pattern}" == "" ] && ! ${append} || [ "${new_value}" == "" ]; then
        color_echo red "safe_find_replace requires filename, pattern and value to be provided"
        color_echo magenta "Provided filename: ${filename}"
        color_echo magenta "Provided pattern: ${pattern}"
        color_echo magenta "Provided value: ${new_value}"
        exit 64
    fi

    # Check to make sure file exists and is normal file, create if needed and specified
    if [ -f "${filename}" ]; then
        debug 10 "${filename} found and is normal file"
    else
        if [ ! -e "${filename}" ] && ${create} ; then
            # Create file if nothing exists with the same name
            debug 10 "Created new file ${filename}"
            ${priv_esc_cmd} touch "${filename}"
        else
            color_echo red "File ${filename} not found or is not regular file"
            exit 74
        fi
    fi

    # Count matches
    num_matches="$(${priv_esc_cmd} grep -c "${pattern}" "${filename}")"

    # Handle replacements
    if [ -n "${pattern}" ] && [ "${num_matches}" -eq "${req_matches}" ]; then
        ${priv_esc_cmd} sed -i -e 's/'"${pattern}"'/'"${new_value}"'/g' "${filename}"
    # Handle appends
    elif ${append} ; then
        if [ "${ini_section}" != "" ]; then
            ini_section_match="$(${priv_esc_cmd} grep -c \"\[${ini_section}\]\" \"${filename}\")"
            if [ "${ini_section_match}" -lt 1 ]; then
                echo -e '\n['"${ini_section}"']\n' | ${priv_esc_cmd} tee -a "${filename}" > /dev/null
            elif [ "${ini_section_match}" -eq 1 ]; then
                ${priv_esc_cmd} sed -i -e '/\['"${ini_section}"'\]/{:a;n;/^$/!ba;i'"${new_value}" -e '}' "${filename}"
            else
                color_echo red "Multiple sections match the INI file section specified: ${ini_section}"
                exit 1
            fi
        else
            echo "${new_value}" | ${priv_esc_cmd} tee -a "${filename}" > /dev/null
        fi
    # Handle opportunistic, no error if match not found
    elif ${opportunistic} ; then
        color_echo magenta "Pattern: ${pattern} not found in ${filename}, continuing"
    # Otherwise exit with error
    else
        color_echo red "Found ${num_matches} matches searching for ${pattern} in ${filename}"
        color_echo red "This indicates a problem, there should be only one match"
        exit 1
    fi
}

# A function to make the ssh environment from a user available to the root
# user when running as a superuser via the priv_esc_cmd function
function link_ssh_config {
    # If root has no ssh config but pre-sudo user does we use the users config during the run
    if ! ${priv_esc_cmd} test -e /root/.ssh/config ; then
        if [ -z "${SUDO_USER_HOME}" ] && [ "${HOME}" != "/root" ]; then
            debug 10 "Did not find SUDO_USER_HOME varible setting to ${HOME}"
            SUDO_USER_HOME="${HOME}"
        fi
        if [ -f "${SUDO_USER_HOME}/.ssh/config" ]; then
            # Make sure .ssh directory exists and has correct permissions
            ${priv_esc_cmd} mkdir -p "/root/.ssh" && sudo chmod 700 "/root/.ssh"
            color_echo green "Copying ${SUDO_USER_HOME}/.ssh/config to /root/.ssh/config for this session"
            color_echo green "Please note that for future/automated r10k runs you might need to make this permanent"
            ${priv_esc_cmd} cp "${SUDO_USER_HOME}/.ssh/config" '/root/.ssh/config'
            ${priv_esc_cmd} chown root "/root/.ssh/config" && ${priv_esc_cmd} chmod 700 "/root/.ssh/config"
            add_on_sig ${priv_esc_cmd} "rm -f /root/.ssh/config"
        fi
    else
        debug 10 "Running as user: $(whoami)"
        debug 10 "Found User home: ${SUDO_USER_HOME}"
        color_echo magenta "Not running as root or root user already has an SSH config, please make sure it's correctly configured as needed for GIT access"
    fi
}

#Creates a tar archive where all paths have been made relative
function create_relative_archive {
    debug 10 "Creating relative archive ${1}"
    local archive_path="${1}"
    local arguments=("${@}")
    local source_elements=("${arguments[@]:1}")
    local transformations=()
    local archive_operation="${archive_operation:-create}"
    assert in_array "${archive_operation}" 'create' 'append' 'update'


    local verbose_flag=''
    if [ "${verbosity}" -ge 5 ]; then
        local verbose_flag=' -v'
    fi
    # Iterate this way to avoid whitespace filename bugs
    num_transformations=${#source_elements[@]}
    for (( i=1; i<num_transformations+1; i++ )) ; do
        if [ -f ${source_elements[${i}-1]} ] ; then
            pattern="$(dirname ${source_elements[${i}-1]} | cut -c 2-)"
        else
            pattern="$(echo ${source_elements[${i}-1]} | cut -c 2-)"

        fi
        transformations+=(" --transform=s,${pattern},,g")
    done

    # shellcheck disable=SC2068
    tar ${transformations[@]} "${verbose_flag}" "--${archive_operation}" --exclude-vcs --directory "${run_dir}" --file "${archive_path}" ${source_elements[@]} || exit_on_fail
}

# Given a filename it will sign the file with the default key
# First parameter is the file to sign the second the output file
# An optional third parameter can be priv_esc_with_env function
# or any other sudo/su command to run as another user
function gpg_sign_file {
    ${3} gpg --armor --sign -o "'${2}' < '${1}'" || exit_on_fail
}

# Reads bash files and inlines any "source" references to a new file
# If second parameter is empty or "-" the new file is printed to stdout
declare -a processed_inline_sources=()
function inline_bash_source {
    local inline_source_file="${1}"
    local inline_dest_file="${2}"
    debug 10 "Inlining file ${inline_source_file} and writing to ${inline_dest_file}"
    declare -a source_file_array
    mapfile -t source_file_array < "${inline_source_file}"
    declare -a combined_source
    declare -a combined_source_array
    # Iterate this way to avoid whitespace bugs
    local lines=${#source_file_array[@]}
    local i
    for (( i=1; i<lines+1; i++ )) ; do
        local filename="$(echo "${source_file_array[${i}-1]}" | grep '^source ' | awk '{print $2}')"
        if [ "${filename}" != "" ] ; then
            debug 10 "Found line with source instruction to file: ${filename}"
            local relative_filename="$(dirname "${inline_source_file}")/$(basename "${filename}")"
            if [ -f "${relative_filename}" ] ; then
                filename="${relative_filename}"
            fi
            if [ ! -f "${filename}" ] ; then
                local try_filename="${run_dir}/${filename}"
                if [ -f "${try_filename}" ] ; then
                    filename="${try_filename}"
                else
                    exit_on_fail "Unable to locate sourced file ${filename}, please make sure source exists"
                fi
            fi
            debug 10 "Injecting source file: ${filename}"
            if ! in_array "${filename}" "${processed_inline_sources[@]:-}" ; then
                debug 10 "No previous import of ${filename} found, recursing"
                # create_secure_tmp will store return data into the first argument
                create_secure_tmp tmp_out_file 'file'
                # shellcheck disable=SC2154
                inline_bash_source "${filename}" "${tmp_out_file}"
                debug 10 "Mapping inlined tmp file ${tmp_out_file}"
                mapfile -t sourced_file_array < "${tmp_out_file}"
                local file_name_no_path="$(basename "${filename}")"
                local base_file_name="${file_name_no_path%.*}"
                local combined_source_array=("${combined_source_array[@]}" \
                    "########## INLINED SOURCE FILE: \"${base_file_name}\" ##########" \
                    "declare -xr ${base_file_name}_stored_bash_opts=\${BASHOPTS}"\
                    "declare -xr ${base_file_name}_stored_shell_opts=\${SHELLOPTS}"\
                    "${sourced_file_array[@]}"\
                    'OLDIFS="${IFS}"'\
                    'IFS=":"'\
                    "for boption in \$${base_file_name}_stored_bash_opts ; do"\
                    '    shopt -qs "${boption}"'\
                    'done'\
                    "for shoption in \$${base_file_name}_stored_shell_opts ; do"\
                    '    set -o "${shoption}"'\
                    'done'\
                    'IFS="${OLDIFS}"'\
                    "########## END INLINED SOURCE FILE: \"${base_file_name}\" ##########")
                processed_inline_sources+=("${filename}")
            fi
        else
            combined_source_array+=("${source_file_array[${i}-1]}")
        fi
    done
    if [ "${inline_dest_file}" == "-" ] || [ "${inline_dest_file}" == "" ]; then
        printf '%s\n' "${combined_source_array[@]}"
    else
        printf '%s\n' "${combined_source_array[@]}" >> "${inline_dest_file}"
        chmod --reference="${inline_source_file}" "${inline_dest_file}"
        debug 10 "Wrote combined source to ${inline_dest_file}"
    fi
}

# Creates an executable tar archive that can extract and run itself
# Note that any script that's provided should not require any parameters
# and should source/include this library file
# Any special commands or things that should be done after extracting the
# archive should be defined in a function called run_if_exec_archive, note that
# the archive will be extracted into a tmp dir name stored in ${tmp_archive_dir}
# Note that run_if_exec_archive will need to be defined before
# importing/sourcing this file
# Note that the archive should be in .tar.gz format
function create_exec_archive {
    # An executable archive is just a bash script concatenated with an archive
    # but separated with a marker __ARCHIVE_FOLLOWS__
    local binary_path="${1}"
    local script_path="${2}"
    local archive="${3}"
    debug 10 "Creating binary ${binary_path} using ${script_path} and ${archive}"
    # create_secure_tmp will store return data into the first argument
    create_secure_tmp tmp_script_file 'file'
    # shellcheck disable=SC2154
    inline_bash_source "${script_path}" "${tmp_script_file}"
    debug 10 "Created temporary inlined script file at: ${tmp_script_file}"
    cat "${tmp_script_file}" > "${binary_path}" || exit_on_fail
    echo '__ARCHIVE_FOLLOWS__' >> "${binary_path}" || exit_on_fail
    cat "${archive}" >> "${binary_path}" || exit_on_fail
    chmod +x "${binary_path}"
    debug 3 "Finished writing binary: ${binary_path}"
}

# Slugifies a string
function slugify {
    echo "${*}" | sed -e 's/[^[:alnum:]._\-]/_/g' | tr -s '-' | tr '[:upper:]' '[:lower:]'
}

# Load default login environment
function get_env {
    # Load all default settings, including proxy, etc
    declare -a env_files
    env_files=('/etc/environment' '/etc/profile')
    for env_file in "${env_files[@]}"; do
	if [ -e "${env_file}" ]; then
	    debug 10 "Sourcing ${env_file}"
            #shellcheck source=/dev/null
	    source "${env_file}"
        else
	    debug 10 "Env file: ${env_file} not present"
	fi
    done
}

# Pick pidfile location if it's ever needed
if [ "${EUID}" -eq "0" ]; then
    pid_prefix="/var/run/"
else
    pid_prefix="/tmp/.pid_"
fi

# Check for or create a pid file for the program
# takes program/pidfile name as a first parameter, this is the unique ID
# Exits with error if a previous matching pidfile is found
function init_pid() {
    pidfile="${pid_prefix}${1}"
    if [ -f "${pidfile}" ]; then
        file_size="$(wc -c < "${pidfile}")"
        file_type="$(file -b "${pidfile}")"
        max_file_size=$(cat < '/proc/sys/kernel/pid_max' | wc -c)
        max_pid=$(cat < /proc/sys/kernel/pid_max)
        if [ "${file_size}" -le "${max_file_size}" ] && [ "${file_type}" == 'ASCII text' ]; then
           pid="$(cat "${pidfile}")"
           if [ "${pid}" -le "${max_pid}" ]; then
               if [ "$(pgrep -cF "${pidfile}")" -eq 1 ]; then
                   color_echo green "Process with PID: ${pid} already running"
                   return 129
               else
                     color_echo red "Pidfile ${pidfile} already exists, but no process found with PID: ${pid}"
                     return 130
                fi
            else
                color_echo red "Pidfile ${pidfile} does not contain a real PID, value ${pid} is larger than max allowed pid of ${max_pid}"
                return 1
            fi
        else
            color_echo red "Pidfile ${pidfile} is either too large or not of type ASCII, make sure it's a real PID file"
            return 1
        fi
    else
        echo "${$}" > "${pidfile}" && add_on_sig "rm -f ${pidfile}"
        return 0
    fi
}

# Send success signal to other process by name
function signal_success() {
    signal "${1}" "SIGCONT" "Success"
}

# Send failure signal to other process by name if send_failure_signal is true
send_failure_signal="${send_failure_signal:-true}"
function signal_failure() {
    if ${send_failure_signal} ; then
        signal "${1}" "SIGUSR2" "Failure"
    fi
}

# Send a signal to process, read pid from file or search by name
# Parameters are: filename/processname signal message
function signal() {
    pidfile="${pid_prefix}${1}"
    # Check if first parameter is pidfile or process name/search string
    if init_pid "${1}" > /dev/null || [ ${?} == 129 ]; then
        other_pids="$(cat "${pidfile}")"
    else
        other_pids="$(pgrep -f -d ' ' "${1}")"
    fi
    if [ "${other_pids}" != "" ]; then
        kill -s "${2}" ${other_pids}
        color_echo cyan "Signalled ${3} to PID(s): ${other_pids}"
    else
        debug 5 "Unable to find process '${1}' to signal"
    fi
}

# Trim whitespaces from strings
function trim {
    local var="${1}"
    var="${var#"${var%%[![:space:]]*}"}"   # remove leading whitespace characters
    var="${var%"${var##*[![:space:]]}"}"   # remove trailing whitespace characters
    echo -n "${var}"
}

# Safely loads config file
# First parameter is filename, all consequent parameters are assumed to be
# valid configuration parameters
function load_config()
{
    config_file="${1}"
    # Verify config file permissions are correct and warn if they are not
    # Dual stat commands to work with both linux and bsd
    shift
    while read -r line; do
        if [[ "${line}" =~ ^[^#]*= ]]; then
            setting_name="$(echo "${line}" | awk -F '=' '{print $1}' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"
            setting_value="$(echo "${line}" | cut -f 2 -d '=' | sed -e 's/^[[:space:]]*//' -e 's/[[:space:]]*$//')"

            if echo "${@}" | grep -q "${setting_name}" ; then
                export ${setting_name}="${setting_value}"
                debug 10 "Loaded config parameter ${setting_name} with value of '${setting_value}'"
            fi
        fi
    done < "${config_file}";
}

# Make sure symlink exists and points to the correct target, will remove
# symlinks pointing to other locations or do nothing if it's correct.
function ln_sf {
    # Check for the minimum number of arguments
    if [ ${#@} -lt 2 ]; then
        color_echo red "Called 'ln_sf' with less than 2 arguments."
        exit_on_fail
    fi

    target_path="${1}"
    link_path="${2}"
    assert test -e "${target_path}"
    debug 10 "Creating symlink at ${2} pointing to ${1}"
    if [ -L "${link_path}" ] ; then
        current_target="$(readlink "${link_path}")"
        if [ "${current_target}" != "${target_path}" ] ; then
            debug 6 "Removing existing symlink: ${link_path}"
            rm -f "${link_path}"
        else
            debug 6 "Current symlink at ${link_path} already points to ${target_path}"
            return 0
        fi
    elif [ -e "${link_path}" ]; then
        color_echo red "Found filesystem object at: ${link_path} but it's not a symlink, fatal error, exiting!"
        exit_on_fail
    fi
    # Create symlink
    ln -s "${target_path}" "${link_path}"
    debug 10 "Successfully created symlink"
}

alias "mantrap"='color_echo green "************,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,**********///****************************************///,    .. .....**/////*,***//////////////////*/////////***
> ,,,,,,,,,,,,,,,,,,,,,,,..,,,,,,,,,,********/////////////////////////////////////********************,,,**///////////////////,,**///////////////////////////*///
> ,,,,,,************,,,,,,,,,,,,,......   .,*/**/*///////*//////////////////////////////******************,,,,**///////////////,,,**///////////////*//(//////////
> ,,,************************,.    ......  ...,******//////////////////////**********///////********************,,*/////////////,,**/////////////////////////////
> /////////////////////////*,.      ......  ....,*//////*////***************,,,,,,,,,,,,,*////*********************,,,*/////////*.,**////////////////////////////
> //////////////////////*,,..        ............,*********/*********************,,,,,,,,,*******************************,**/////*///////////////////////////////
> */////////////////*,,....              ........,,,*****//*******************,**,,,**,**************************************///////*//////////////(/////////////
> ***********//////,......                .....,,,,,,,,**/////************,,,,,(#######*/%%%%%%%%%%###%%#/%%%%#//**(#&@@@@@&%(**////////////#%%%%%%%%%%(///(/////
> **********//////,......                 .....,,,,,,,,,,*********,,,,,,,,,,,,,%@@@@@@&,/@@@@@@@@@@@@@@@@(@@@@&/*(@@@@@@@@@@@@@(*////*//////&@@@@@@@@@@%///((///*
> ***************,.........     .          ...,,,,,,,,,,,,,,,,,,..             #@@@@@@&./@@@@@@@@@@@@@@@@/@@@@&*(@@@@@@@@@@@@@@@#***////////&@@@@@@@@@@&/((((((/*
>              ,,,,,.....  ......... ....  ...,,,,,,,,,**,.                    #@@@@@@&.*###%&@@@@@@%####,#@@@(,%@@@@@@#*(@@@@@@&*****/////(@@@@@@@@@@@@(((((((/*
>              *,,,,.,. .. ....      .. .  ...,,,,,,,,,,**,                    #@@@@@@&.    ,%@@@@@@/    .&@@#  %@@@@@@#*(@@@@@@&*******///#@@@@@@@@@@@@#((((((/*
>             ****,,,........        ....   ..,,,,,,,,,,**,   . .*,.           #@@@@@@&.    ,%@@@@@@/    ./.    #@@@@@@@/*///////********/(%@@@@@&%@@@@@%((((((/*
>             ((*,,.,*,...      ......      ..,,,,,,,,,,**,   .  .,.           #@@@@@@&.    ,%@@@@@@/           ,@@@@@@@@@**************(&@@@@@##@@@@@&((((((/*
>             /(. ,,*(/*,. . .......        ..,,,,,,,,,,,*,      . .           #@@@@@@&.    ,%@@@@@@/            ,&@@@@@@@@@@&(***********%@@@@@@((@@@@@@#(((((/*
>             ./ .,..  ..... .......  ..... ..,,,,,,,,,,***,                   #@@@@@@&.    ,%@@@@@@/              /%@@@@@@@@@@%**********&@@@@@@((&@@@@@#(((((/*
>              ........      ......  ...... ..,,,,,,,,,****.  .,,,             #@@@@@@&.    ,%@@@@@@/                 *&@@@@@@@@&********/@@@@@@&//&@@@@@((((/*
>  .      .,....    . ..       ...  ..........,,,,**,,**,*.. ..,,,,            #@@@@@@&.    *%@@@@@@/           /%%%%%%/ #@@@@@@@/*******(@@@@@@@&&&@@@@@@%((((/*
>  ..    ,,......... ...    .   ...........  .,,,,,.,,****.  .,,,**,           #@@@@@@&.    ,%@@@@@@/           (@@@@@@(  &@@@@@@#*******%@@@@@@@@@@@@@@@@&((((/*
>  ,,.  .,........... .     . .............. ..,,,,.,,,,**. ...,*,.            #@@@@@@&.    ,%@@@@@@/           /@@@@@@(  %@@@@@@#*******&@@@@@@@@@@@@@@@@@(((((/
>  ...  ..   .    ....       ..... . .   .......,,,,,,..,*   ....,             #@@@@@@&.    ,%@@@@@@/           ,@@@@@@&*(@@@@@@@,******/@@@@@@@&//(@@@@@@@#((((/
>    ... . ...                ...  ...     .....,,,.   .*,  .. .,.             #@@@@@@&.    ,%@@@@@@/            /@@@@@@@@@@@@@@(   ****/@@@@@@@%//(@@@@@@@%((((/
>   ..,.**, ...     .        .... ...     ......,**/,   .*  .//,..             (&&&&&&%.    ,#&&&&&&*              *#@@@@@@@@&/      ***#@@@@@@@(//(&@@@@@@&(((((
>     ..,**. .,......       .. ....       .......,*//... .. .,..,                                                      .....          ***********////((((((((((((
>           .  ....      ..    ...,. .. ....       .,*..........               #@@@@@@@@@@@@@@@@# #@@@@@@@@@@@&%(.       %@@@@@@@@@@@. ***#&@@@@@@@@@@@&%#(((((((
>            ,(*.          .,.(/*,                    .,,...                   #@@@@@@@@@@@@@@@@# #@@@@@@@@@@@@@@@%.    .@@@@@@@@@@@@/  **#@@@@@@@@@@@@@@@@#(((((
>       ,*////(/,.          ,               .           .                      #@@@@@@@@@@@@@@@@# #@@@@@@@%&@@@@@@@#,   *@@@@@@@@@@@@%  .*#@@@@@@@@&@@@@@@@@(((((
>  .**********//,,         .*,,.            ......   ....                      ....*@@@@@@@%....  #@@@@@@@, ,@@@@@@&*   (@@@@@@@@@@@@&.  .#@@@@@@@@//&@@@@@@#((((
> **************,,.          ...     ....          ......                          ,@@@@@@@%      #@@@@@@@, .&@@@@@&/   %@@@@@@#@@@@@@,   (&@@@@@@@//&@@@@@@#((((
> ,,,***********,,.                     .........,,,,,,,,                          ,@@@@@@@%      #@@@@@@@, ,@@@@@@%,  .@@@@@@&*@@@@@@(   (&@@@@@@@/*&@@@@@@#((((
> ,,*,*****,,****,.                           . ...,,,***(*                        ,@@@@@@@#      #@@@@@@@&@@@@@@@@/   ,@@@@@@%.@@@@@@%   (&@@@@@@@/(@@@@@@@#((((
> *,,,*****,,,****,.                   .        .....,,,(((#(//***,.               ,@@@@@@@#      #@@@@@@@@@@@@@%*     (@@@@@@( &@@@@@@.  (&@@@@@@@@@@@@@@@&(((((
> *,,,*****,,,,,***,.                        ...,,*, .*/((((((((*.                 ,@@@@@@@#      #@@@@@@@##&@@@@@@,   %@@@@@@, %@@@@@@*  (&@@@@@@@@@@@@@&%((((((
> *,,,,,,,*,,,,,,,*,,.                       ..,,,, .*(##((((((((///,.             ,@@@@@@@#      #@@@@@@@, .@@@@@@%* .@@@@@@@, (@@@@@@#  (&@@@@@@&/*******((((((
> ,,,,,,,,**,,,,,,,***,               .      ..,,  .*/(#((((((((((/*,              ,@@@@@@@#      #@@@@@@@, .@@@@@@&/ ,@@@@@@@@@@@@@@@@&  (&@@@@@@@/*******/(((((
> ,,,,,,,,,,,,,,,,,,,***/*.           .           ,/((###(((((((((/                ,@@@@@@@%      #@@@@@@@, .@@@@@@&/ (@@@@@@@@@@@@@@@@@, (&@@@@@@@/********(((((
> ,,,,,,,,,,,,,,,,,,,,,,,**/*,.                .*/(((####((((((((((.               ,@@@@@@@%      #@@@@@@@, .@@@@@@&/ %@@@@@@@%%%@@@@@@@( (&@@@@@@@/********/((((
> ,,,,,,,,,,,,,,,,,,,,,,,,,,,**********,,***////(((######((((((((((#,              ,@@@@@@@%      #@@@@@@@, .@@@@@@&/.@@@@@@@&. .@@@@@@@% (&@@@@@@@/*********((((
> ,,,,,,,,,,,,,,,,,,,,,,,,,.,,,,,*******/////(((((#######((((((((((##.             ,@@@@@@@#      #@@@@@@@, .&@@@@@&/,@@@@@@@&  .&@@@@@@&.(&@@@@@@@/**,,*****/(((
> ,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,****///((((((#####((((((((((((###*           .*******,      ,*******.  *******.,/(/****,   *//*/***..******((/**,,,*****(((
> ,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,,******/////((((((#####((((((((((((((((                                               ..,,.           .         ,*****,,*****/((
> ,,,,,,,,,,,,,,,,,,,,,,,,,,,**********//////(((((((#####(((((((((((((((.                                                 ..,.      .,,,..        ,****,,,,****((
> ..,,,,,,,,,,,,,,,,,,..,,,,,,***///////////////((((#####((((((((((((((#.                .                                  ....   .,,,..         .****,,,,****((
> .........,,,,,,,,,,,......,,,**////////////////((((((##(((((((((((((##.                                                .   ...,,,,,,..           ,***,,,,****/("'


# Unit tests
function test_shtdlib()
{
    color_echo green "Testing shtdlib functions"
    color_echo cyan "OS Family is: ${os_family}"
    color_echo cyan "OS Type is: ${os_type}"
    color_echo cyan "Local IPs are:"
    for ip in ${local_ip_addresses} ; do
        color_echo cyan "${ip}"
    done
    color_echo cyan "Testing echo colors:"
    color_echo black "Black"
    color_echo red "Red"
    color_echo green "Green"
    color_echo yellow "Yellow"
    color_echo blue "Blue"
    color_echo magenta "Magenta"
    color_echo cyan "Cyan"
    color_echo blank "Blank"
    assert true
    assert whichs ls
    assert [ 0 -eq 0 ]
    declare -a shtdlib_test_array
    shtdlib_test_array=(a b c d e f g)
    assert in_array 'a' "${shtdlib_test_array[*]}" && color_echo cyan "\'a\' is in \'${shtdlib_test_array[*]}\'"
    orig_verbosity="${verbosity:-1}"
    verbosity=1 && color_echo green "Verbosity set to 1 (should see debug up to 1)"
    for ((i=1; i <= 11 ; i++)) ; do
        debug ${i} "Debug Level ${i}"
    done
    verbosity=10 && color_echo green "Verbosity set to 10 (should see debug up to 11)"
    for ((i=1; i <= 11 ; i++)) ; do
        debug ${i} "Debug Level ${i}"
    done
    verbosity="${orig_verbosity}"
    shtdlib_test_variable='/home/test'
    finalize_path shtdlib_test_variable
    finalize_path '~'
    finalize_path './'
    finalize_path '$HOME/test'
    finalize_path '\tmp'

    # Test safe loading of config parameters
    tmp_file="$(mktemp)"
    add_on_sig "rm -f ${tmp_file}"
    test_key='TEST_KEY'
    test_value='test value moretest -f /somepath ./morepath \/ping ${}$() -- __'
    echo "${test_key}=${test_value}" > "${tmp_file}"
    load_config "${tmp_file}" 'TEST_KEY'
    # shellcheck disable=SC2153
    test "'${TEST_KEY}'" == "'${test_value}'" || exit_on_fail

    # Test version comparison
    assert compare_versions '1.1.1 1.2.2test'
    assert ! compare_versions '1.2.2 1.1.1'
    assert compare_versions '1.0.0 1.1.1 2.2.2'
    assert [ "$(compare_versions '4.0.0 3.0.0 2.0.0 1.1.1test 1.0.0')" == '4' ]

    # Test resolving domain names
    assert [ "$(resolve_domain_name example.com)" == '93.184.216.34' ]
}

# Test bash version
if compare_versions "${BASH_VERSION}" 4 ; then
    debug 9 "Detected bash version ${BASH_VERSION}, for optimal results we suggest using bash V4 or later"
fi
