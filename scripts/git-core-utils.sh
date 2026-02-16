# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.

#!/bin/bash

set -euo pipefail

# Testing function
# - set to 1 to mock docker and git commands
mock_test_mode=0
if [ "${mock_test_mode:-0}" -eq 1 ]; then
    git() {
        printf '%s\n' "[MOCK] git $*"
    }
fi

# Global variables
working-branch="$(git branch --show-current)"

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
    local message="${1:-}"

    while true; do
        if [ -z "$message" ]; then
            read -r -p "Enter a commit message: " message
        fi
    done
}