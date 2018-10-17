#!/bin/bash

# Library download function, optionally accepts a full path/name and URL
function download_lib {
    tmp_path="${1:-$(mktemp)}"
    lib_url="${2:-https://raw.githubusercontent.com/sdelements/shtdlib/master/shtdlib.sh}"
    curl -s -l -o "${tmp_path}" "${lib_url}" || wget --no-verbose "${lib_url}" --output-document "${tmp_path}" || return 1
}

# Library install function, optionallly accepts a URL and a full path/name
# shellcheck disable=SC2120,SC2119
function install_lib {
    lib_path="${1:-/usr/local/bin/shtdlib.sh}"
    lib_name="$(basename "${lib_path}")"
    tmp_path="$(mktemp)"

    echo "Installing library ${lib_name} to ${lib_path}"
    download_lib "${tmp_path}"
    mv "${tmp_path}" "${lib_path}" || sudo mv "${tmp_path}" "${lib_path}" || return 1
    chmod 755 "${lib_path}" || sudo chmod 755 "${lib_path}" || return 1
    # shellcheck disable=SC1091,SC1090
    source "${lib_path}"
    color_echo green "Installed ${lib_name} to ${lib_path} successfully"
}

# Library import function, accepts one optional parameter, name of the file to import
# shellcheck disable=SC2120,SC2119
function import_lib {
    lib_name="${1:-'shtdlib.sh'}"
    full_path="$(readlink -f "${BASH_SOURCE[0]}" 2> /dev/null || realpath "${BASH_SOURCE[0]}" 2> /dev/null || greadlink -f "${BASH_SOURCE[1]}" 2> /dev/null:-"${0}")"
    # Search current dir and walk down to see if we can find the library in a
    # parent directory or sub directories of parent directories named lib/bin
    while true; do
        pref_pattern=( "${full_path}/${lib_name}" "${full_path}/lib/${lib_name}" "${full_path}/lib/${lib_name}" )
        for pref_lib in "${pref_pattern[@]}" ; do
            if [ -e "${pref_lib}" ] ; then
                echo "Importing ${pref_lib}"
                # shellcheck disable=SC1091,SC1090
                source "${pref_lib}"
                return 0
            fi
        done
        full_path="$(dirname "${full_path}")"
        if [ "${full_path}" == '/' ] ; then
            # If we haven't found the library try the PATH or install if needed
            # shellcheck disable=SC1091,SC1090
            source "${lib_name}" 2> /dev/null || install_lib && return 0
            # If nothing works then we fail
            echo "Unable to import ${lib_name}"
            return 1
        fi
    done
}


# Import the shell standard library
# shellcheck disable=SC2119
import_lib
