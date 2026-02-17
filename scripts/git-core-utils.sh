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
__CORE_UTILS_LOADED=1

# Testing function
 # - run 'TEST_MODE=1 <script name> [args]'
: "${TEST_MODE:=0}"
if [ "$TEST_MODE" -eq 1 ]; then
    git() {
        printf '%s\n' "[MOCK] git $*"
    }
fi

# GLOBAL VARIABLES - keeping here for now, load in scripts that need it
# working_branch="$(git symbolic-ref --short HEAD 2>/dev/null || echo '')"

# Functions



# yes or no
yes_no() {
    local message="${1:-"Null"}"

    while :; do
        if ! read -r -p "$message [y/N]: " REPLY; then
            printf '\nAborted.\n' >&2
            return 1
        fi

        case "$REPLY" in
        [yY]|[yY][eE][sS])
            return 0
            ;;
        ""|[nN]|[nN][oO])
            return 1
            ;;
        *)
            printf 'Invalid choice.\n' >&2
            ;;
        esac
    done
}

# check for staged files
check_files_staged() {
    if git diff --cached --quiet --; then
        printf '\nNo files are staged for commit.\n' >&2
        
        if yes_no "Stage all tracked and untracked files now?"; then
            git add -A
            # check for staged files again to make sure fr
            if git diff --cached --quiet --; then
                printf '\nAbort: working tree is clean. Nothing to stage.\n' >&2
                return 1
            fi
        else
            printf '\nCommit aborted.\n' >&2
            return 1
        fi
    fi
}

# enter commit message
commit_message_check() {
    REPLY="${1:-}"

    while :; do
        case "$REPLY" in
            *[![:space:]]*) break ;;
        esac

        if ! read -r -p "Enter a commit message: " REPLY; then
            printf '\nCommit aborted.\n' >&2
            return 1
        fi
    done
}