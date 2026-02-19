# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.

#!/bin/bash

# Include guard to prevent redundant parsing
if [ -n "${__BRANCH_UTILS_LOADED:-}" ]; then
    return 0
fi
__BRANCH_UTILS_LOADED=1

__CORE_UTILS_LOADED="${__CORE_UTILS_LOADED:-0}"

if [ "$__CORE_UTILS_LOADED" -eq 0 ]; then
    . "$GIT_SCRIPTS_HOME_DIR/lib/git-core-utils.sh"
fi

# FUNCTIONS

check_clean_tree() {
    if [ -n "$(git status --porcelain)" ]; then
        printf "\nAbort: Working tree is dirty.\n"
        return 1
    fi
}

start_branch() {

}

finish_branch() {

}

delete_branch() {
    local delete_choice="${1:-$working_branch}"
    local force_mode="${2:-}"
    local switched_branch=0

    detect_protected_branch "del_branch" "$delete_choice" || return 1
    check_clean_tree || return 1

    if [ "$delete_choice" = "$working_branch" ]; then
        git switch next || {
                printf '\nFailed to switch to next (does it exist?)\n'
                return 1
            }
        switched_branch=1
    fi

    case "$force_mode" in
        yes|-y|--yes|--y|y|d|-d|--d|--delete)
            printf '\nDeleting.\n' >&2
            ;;
        *)
            if yes_no "Delete '$delete_choice' locally and remotely?"; then
                printf '\nDeleting.\n' >&2
            else
                printf '\nDeletion aborted.\n' >&2
                return 1
            fi
            ;;
    esac

    git branch -d "$delete_choice"
    git push origin --delete "$delete_choice" || printf 'Remote delete failed (maybe already gone)' >&2
    printf "\nBranch $delete_choice deleted locally and remotely.\n"
}