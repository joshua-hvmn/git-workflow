#!/bin/bash

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.

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
    if [ -n "$(git ls-files --others --exclude-standard)" ]; then
        printf "\nAbort: Working tree has files I can't autostash.\n"
        return 1
    fi
}
check_for_branch() {
    local target_branch="${1:-"next"}"
    if ! git rev-parse --verify "$target_branch" >/dev/null 2>&1; then
        printf "\nError: could not find local 'next' branch.\n" >&2
        return 1
    fi
}

start_branch() {
    local start_mode="${1:-}"
    local new_branch_name="${2:-"null"}"
    local new_branch_type="topic"
    local base_branch="next"
    local full_branch_name
    local start_message="Enter new topic branch name: "

    
    if [ -z "$start_mode" ]; then
        printf '\nError: usage: git b start <topic|hotfix|release> [branch-name]\n' >&2
        return 1
    fi

    check_clean_tree || return 1

    git fetch --all --prune >/dev/null 2>&1 || true

    check_for_branch "next"

    case "$start_mode" in
        topic|t|-t|--topic)
            :
            ;;
        hotfix|h|-h|--hotfix)
            new_branch_type="hotfix"
            base_branch="main"
            start_message="Enter new hotfix name (e.g., v1.2.3): "
            ;;
        release|r|-r|--release)
            new_branch_type="release"
            start_message="Enter new release name (e.g., v1.2.3): "
            ;;
        *)
            echo "ERROR: unknown mode: $start_mode"
            return 1
            ;;
    esac

    get_user_input "$new_branch_name" "$start_message"
    new_branch_name="$REPLY"
    
    if [ "$new_branch_type" != "topic" ]; then
        full_branch_name="$new_branch_type/$new_branch_name"
    else
        full_branch_name="$new_branch_name"
    fi

    printf "\nStarting %s branch '%s' from '%s'...\n" "$new_branch_type" "$full_branch_name" "$base_branch" >&2
    rb_pull_function "$base_branch" || return 1
    git switch -c "$full_branch_name" "$base_branch"
    git push -u origin "$full_branch_name"
}

finish_branch() {
    local finish_choice="${1:-$working_branch}"
    local finish_type
    local finish_version

    detect_protected_branch "fin_branch" "$finish_choice" || return 1
    check_clean_tree || return 1
    git fetch --all --prune >/dev/null 2>&1 || true
    check_for_branch "next"

    case "$finish_choice" in
        hotfix/*|release/*)
            finish_type="${finish_choice%/*}"
            finish_version="${finish_choice#*/}"
            if ! yes_no "Merge '$finish_choice' into main and next, push changes and tag?"; then
                return 1
            fi
            rb_pull_function "main"
            git merge --no-ff "$finish_choice" || return 1
            git tag -a "$finish_version" -m "$finish_type: $finish_version" || return 1
            rb_pull_function "next" || return 1
            if git merge --ff-only main 2>/dev/null; then
                :
            else
                git merge --no-edit main || return 1
            fi
            git push origin main next --tags || return 1
            delete_branch "$finish_choice" || return 1
            ;;
        *)
            if ! yes_no "Merge '$finish_choice' into next, push changes?"; then
                return 1
            fi
            rb_pull_function "next" || return 1
            git merge --no-ff "$finish_choice" || return 1
            git push origin next || return 1
            delete_branch "$finish_choice" || return 1
            ;;
    esac
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