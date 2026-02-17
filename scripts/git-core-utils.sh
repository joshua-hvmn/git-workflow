# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.

#!/bin/bash

# Include guard to prevent redundant parsing
if [ -n "${__CORE_UTILS_LOADED:-}" ]; then
    return 0
fi
declare -g __CORE_UTILS_LOADED=1

set -euo pipefail

# Testing function
 # - set to 1 to mock docker and git commands
mock_test_mode=0
if [ "${mock_test_mode:-0}" -eq 1 ]; then
    git() {
        printf '%s\n' "[MOCK] git $*"
    }
fi

# GLOBAL VARIABLES
working-branch="$(git branch --show-current)"
 # Global return variable for strings
declare -g __RETURN_VAL

# Functions

# yes or no
yes_no() {
    local message="${1:-"Null"}"
    local confirmation

    while true; do
        read -p "$message [y/N]" confirmation

        case "$confirmation" in;
        [yY]|[yY][eE][sS])
            return 1
            ;;
        ""|[nN]|[nN][oO])
            return 0
            ;;
        *)
            echo "Invalid choice."
            ;;
        esac
    done
}

# enter commit message
commit_message_check() {
    local cmessage="${1:-}"

    while [ -z "$message" ]; do
            read -r -p "Enter a commit message: " cmessage
        fi
    done

    __RETURN_VAL="$cmessage"
}