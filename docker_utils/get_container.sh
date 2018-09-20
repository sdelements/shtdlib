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

# Import the standard shell library
# shellcheck source=../shtdlib.sh disable=SC1091
source "$(dirname "${0}")/../shtdlib.sh" &> /dev/null || ../shtdlib.sh &> /dev/null || source ./shtdlib.sh &> /dev/null || source shtdlib.sh

# A helper function to ensure containers exist locally before launch
function get_container {
    debug 10 "get_container called with: ${*}"
    args=( "${@}" )
    if [ "${#args[@]}" -lt 3 ] ; then
        color_echo red "${0} needs at least three arguments, none were provided"
        return 64
    elif [ "${#args[@]}" -gt 1 ] ; then
        repo="${args[0]}"
        path="${args[1]}"
        tag="${args[2]}"
    fi
    mapfile -t available_versions < <( docker images "${repo}${path}*" --filter label=org.opencontainers.image.name --format "{{.Tag}}" | grep -v "<none>" ) 
    if ! in_array "${tag}" "${available_versions[@]:-}" ; then
        color_echo yellow "Selected container (${repo}${path}:${tag}) not found, attempting pull from upstream repository"
        if docker pull "${repo}${path}:${tag}" ; then
            color_echo green 'Successfully pulled.'
        else
            color_echo red "Error: Container (${repo}${path}:${tag}) not found in upstream repository, giving up."
            exit 1
        fi
    else
        color_echo cyan "Selected container (${repo}${path}:${tag}) already found locally, skipping pull."
    fi
}
