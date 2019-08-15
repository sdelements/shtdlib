#!/usr/bin/env bash

default_library_name='shtdlib.sh'
default_base_download_url='https://raw.githubusercontent.com/sdelements/shtdlib/master'
default_install_path='/usr/local/bin'

# Temporary debug function
type -t import | grep -q '^function$' || function debug { echo "${@:2}" ; }

# Import or source
function import_or_source {
    # Import prevents the same source files from being imported multiple times
    # and preserves the order definition for variables and functions since they
    # don't get overwritten by subsequent imports.
    local library="${1}"
    shift
    if type -t import | grep -q '^function$' ; then
        debug 10 "Trying to import ${library}"
        import "${library}"
    else
        # shellcheck disable=1090
        if [ -e "${library}" ] ; then
            debug 10 "Trying to source ${library}"
            source "${library}"
        else
            return 1
        fi
    fi
}

# Library download function, optionally accepts a full path/name and URL
function download_lib {
    local tmp_path="${1:-$(mktemp)}"
    local lib_url="${2:-${default_base_download_url}/${default_library_name}}"
    curl -s -l -o "${tmp_path}" "${lib_url}" || wget --no-verbose "${lib_url}" --output-document "${tmp_path}" || ( echo "Failed to download ${2}" && return 1)
}

# Library install function, optionallly accepts a URL and a full path/name
# shellcheck disable=SC2120,SC2119
function install_lib {
    local lib_path="${1:-${default_install_path}/${default_library_name}}"
    local lib_name="${2:-$(basename "${lib_path}")}"
    local tmp_path="${3:-$(mktemp)}"

    echo "Installing library ${lib_name} to ${lib_path}"
    download_lib "${tmp_path}" "${default_base_download_url}/${lib_name}" || return 1
    mv "${tmp_path}" "${lib_path}" || sudo mv "${tmp_path}" "${lib_path}" || lib_path="${tmp_path}"
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
                return 1
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
