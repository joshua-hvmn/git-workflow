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

# GLOBAL VARIABLES - keeping here for now, load in scripts that need it

# Functions
get_working_branch() {
    git symbolic-ref --short HEAD 2>/dev/null || echo ''
}

get_user_input() {
    local user_input="${1:-}"
    local prompt_msg="${2:-}"
    REPLY=""
    if [ -z "$user_input" ] || [ "$user_input" = "null" ]; then
        while true; do
            read -r -p "$prompt_msg " REPLY
            if [ -n "$REPLY" ]; then
                break
            fi
        done
    else
        REPLY="$user_input"
        return 0
    fi
}

# Testing function
 # - run 'TEST_MODE=1 <script name> [args]'
 # - sets working branch
: "${TEST_MODE:=0}"
if [ "$TEST_MODE" -eq 1 ]; then
    git() {
        printf '%s\n' "[MOCK] git $*"
    }
    working_branch="dev"
else
    working_branch=$(get_working_branch) || :
fi

# detect protected branch
# - pass "commit" or "push"
detect_protected_branch() {
    local type_msg="${1:-}"
    local current_branch="${2:-$working_branch}"

    case "$current_branch" in
        main|master|next|dev)
            case "$type_msg" in
                "del_branch")
                    printf "\nAbort: you cannot delete $current_branch.\n" >&2
                    return 1
                    ;;
                "fin_branch")
                    printf "\nAbort: you cannot finish $current_branch.\n" >&2
                    return 1
                    ;;
            esac
            if yes_no "On $current_branch, are you sure you want to $type_msg?"; then
                :
            else
                printf "\nAborted\n" >&2
                return 1
            fi
            ;;
    esac
}

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
commit_pre_checks() {
    local mode="${1:-}"
    shift

    if [ "$mode" != "amend" ]; then
        check_files_staged || return 1
    fi
    commit_message_check "$@" || return 1
}
# commit function, call this in quick commit
commit_function() {
    if [ "${1:-}" = "--amend" ]; then
        shift
        commit_pre_checks "amend" "$@"
        git commit --amend -m "$REPLY"
        return 0
    fi
    commit_pre_checks "normal" "$@"
    git commit -m "$REPLY"
}

# rb-pull
rb_pull_function() {
    local current="${1:-$working_branch}"
    if [ -z "$current" ]; then
        printf '\nNot on a branch.\n' >&2
        return 1
    fi
    
    git switch "$current"
    
    # Record old stash
    old_stash=$(git rev-parse -q --verify refs/stash 2>/dev/null || :)
    
    git stash push -u -m "git-rb-pull autostash" || true
    
    # Record new stash
    new_stash=$(git rev-parse -q --verify refs/stash || echo "")
    
    git pull --rebase origin "$current"
    
    # Pop if necessary
    if [ "$old_stash" != "$new_stash" ]; then
        git stash pop || return 1
    fi
}

conditional_rb_pull() {
    if git ls-remote --exit-code --heads origin "$working_branch" > /dev/null 2>&1; then
        printf "\nBranch exists on remote. Syncing...\n" >&2
        rb_pull_function "$working_branch"
    fi
}