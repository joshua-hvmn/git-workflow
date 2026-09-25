#!/bin/bash

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.

# shellcheck disable=SC2034
# globals here are consumed by the scripts that source this file

# Include guard to prevent redundant parsing
if [ -n "${__CORE_UTILS_LOADED:-}" ]; then
    return 0
fi
__CORE_UTILS_LOADED=1

# OUTPUT HELPERS
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
    __C_RED=$'\033[31m' __C_YEL=$'\033[33m' __C_BLU=$'\033[34m' __C_RST=$'\033[0m'
else
    __C_RED='' __C_YEL='' __C_BLU='' __C_RST=''
fi

info() { printf '%s\n' "$*" >&2; }
note() { printf '%s%s%s\n' "$__C_BLU" "$*" "$__C_RST" >&2; }
warn() { printf '%sWarning:%s %s\n' "$__C_YEL" "$__C_RST" "$*" >&2; }
err() { printf '%sError:%s %s\n' "$__C_RED" "$__C_RST" "$*" >&2; }

# ---------------------------------------------------------------------------
# Configuration
#
# Everything is read from `git config`, so it can be set globally
# (~/.gitconfig) or per repository (.git/config) with no extra config file:
#
#   git config workflow.mainBranch      main      # production branch
#   git config workflow.devBranch       next      # integration branch (set = mainBranch for trunk/GitHub flow)
#   git config workflow.remote          origin
#   git config workflow.releasePrefix   release/
#   git config workflow.hotfixPrefix    hotfix/
#   git config workflow.prereleaseLabel rc        # default label for `git b prerelease`
#   git config workflow.strict          false     # true = flow violations abort instead of asking
#   git config --add workflow.protected staging   # extra protected branches (multi-valued)
#
# ---------------------------------------------------------------------------

# Defaults, then one `git config` call reads every workflow.* key at once
# (git prints keys lowercased, hence the lowercase patterns).
MAIN_BRANCH=main
DEV_BRANCH=next
REMOTE=origin
RELEASE_PREFIX=release/
HOTFIX_PREFIX=hotfix/
PRERELEASE_LABEL=rc
STRICT=false
EXTRA_PROTECTED=''

while read -r __key __value; do
    case "$__key" in
    workflow.mainbranch) MAIN_BRANCH="$__value" ;;
    workflow.devbranch) DEV_BRANCH="$__value" ;;
    workflow.remote) REMOTE="$__value" ;;
    workflow.releaseprefix) RELEASE_PREFIX="$__value" ;;
    workflow.hotfixprefix) HOTFIX_PREFIX="$__value" ;;
    workflow.prereleaselabel) PRERELEASE_LABEL="$__value" ;;
    workflow.protected) EXTRA_PROTECTED="$EXTRA_PROTECTED $__value" ;;
    workflow.strict)
        # A bare `strict` with no value means true, same as git's own booleans
        case "$__value" in
        '' | [Tt][Rr][Uu][Ee] | [Yy][Ee][Ss] | [Oo][Nn] | 1) STRICT=true ;;
        *) STRICT=false ;;
        esac
        ;;
    esac
done < <(git config --get-regexp '^workflow\.' 2>/dev/null || true)
unset __key __value

# GitHub / Trunk-based flow: no separate integration branch
if [ "$DEV_BRANCH" = "$MAIN_BRANCH" ]; then
    TRUNK_MODE=1
else
    TRUNK_MODE=0
fi

# Functions
get_working_branch() {
    git symbolic-ref --short HEAD 2>/dev/null || echo ''
}

working_branch=$(get_working_branch) || :

require_branch() {
    if [ -z "$working_branch" ]; then
        err "not on a branch (detached HEAD). Switch to a branch first."
        return 1
    fi
}

get_user_input() {
    local user_input="${1:-}"
    local prompt_msg="${2:-}"
    REPLY=""
    if [ -z "$user_input" ]; then
        while true; do
            read -r -p "$prompt_msg " REPLY || return 1
            if [ -n "$REPLY" ]; then
                break
            fi
        done
    else
        REPLY="$user_input"
        return 0
    fi
}

# yes or no
yes_no() {
    local yn_message="${1:-"Null"}"
    local yn_default="${2:-n}"
    local yn_options

    case "$yn_default" in
    [yY] | [yY][eE][sS])
        yn_options="[Y/n]"
        yn_default="y"
        ;;
    *)
        yn_options="[y/N]"
        yn_default="n"
        ;;
    esac
    while :; do
        if ! read -r -p "$yn_message $yn_options: " REPLY; then
            printf '\nAborted.\n' >&2
            return 1
        fi

        if [ -z "$REPLY" ]; then
            REPLY="$yn_default"
        fi

        case "$REPLY" in
        [yY] | [yY][eE][sS])
            return 0
            ;;
        [nN] | [nN][oO])
            return 1
            ;;
        *)
            printf 'Invalid choice.\n' >&2
            ;;
        esac
    done
}

# Flow violations: abort in strict mode, otherwise, warn and ask.
# Returns 0 to continue and 1 to abort
flow_warn() {
    warn "$1"
    if [ "$STRICT" = "true" ]; then
        err "aborting (workflow.strict is enabled)."
        return 1
    fi
    yes_no "Continue anyway?" || {
        info "Aborted."
        return 1
    }
}

is_protected_branch() {
    local branch="$1" p
    for p in "$MAIN_BRANCH" "$DEV_BRANCH" $EXTRA_PROTECTED; do
        [ "$branch" = "$p" ] && return 0
    done
    return 1
}

# detect protected branch
# - pass "commit", "push", "del_branch" or "fin_branch"
detect_protected_branch() {
    local type_msg="${1:-}"
    local current_branch="${2:-$working_branch}"

    is_protected_branch "$current_branch" || return 0

    case "$type_msg" in
    del_branch)
        err "you cannot delete protected branch '$current_branch'."
        return 1
        ;;
    fin_branch)
        err "you cannot finish protected branch '$current_branch'."
        return 1
        ;;
    esac
    flow_warn "'$current_branch' is a protected branch; you are about to $type_msg directly on it."
}

# check for staged files
check_files_staged() {
    if git diff --cached --quiet --; then
        info "No files are staged for commit."
        git status -sb
        if yes_no "Stage all tracked and untracked files now?" "y"; then
            git add -A
            # check for staged files again to make sure
            if git diff --cached --quiet --; then
                err "working tree is clean. Nothing to stage."
                return 1
            fi
        else
            info "Commit aborted."
            return 1
        fi
    fi
    return 0
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
        if [ "$#" -eq 0 ]; then
            git commit --amend --no-edit
            return
        fi
        commit_pre_checks "amend" "$*" || return 1
        git commit --amend -m "$REPLY"
        return
    fi
    commit_pre_checks "normal" "$*" || return 1
    git commit -m "$REPLY"
}

# ---------------------------------------------------------------------------
# Remote state
#
# Each fetch/ls-remote/pull/push is a separate SSH connection to the remote,
# which is where nearly all the time goes. So: fetch once per command
# (sync_remote), then answer every "does it exist on the remote?" question
# from the local remote-tracking refs instead of asking the network again.
# ---------------------------------------------------------------------------
__SYNCED=0

sync_remote() {
    [ "$__SYNCED" -eq 1 ] && return 0
    __SYNCED=1
    # --tags also fetches all tags; --prune drops deleted remote branches
    # (it does not delete local-only tags)
    git fetch --quiet --prune --tags "$REMOTE" ||
        warn "could not fetch from '$REMOTE'; using the last known remote state."
}

# Answered locally from refs/remotes/<remote>/*; call sync_remote first for fresh data.
remote_branch_exists() {
    git show-ref --verify --quiet "refs/remotes/$REMOTE/$1"
}

# rb-pull: switch to a branch and bring it up to date with the remote
rb_pull_function() {
    local current="${1:-$working_branch}"
    if [ -z "$current" ]; then
        err "Not on a branch."
        return 1
    fi

    sync_remote

    git switch "$current" || return 1

    remote_branch_exists "$current" || return 0

    if is_protected_branch "$current"; then
        # main/next should never have local-only commits. A rebase here would
        # flatten any unpushed merge commits (e.g. after a failed finish), so
        # only fast-forward, and stop if the branch has diverged.
        git merge --ff-only "$REMOTE/$current" || {
            err "local '$current' has diverged from '$REMOTE/$current'; resolve it by hand."
            return 1
        }
    else
        git rebase --autostash "$REMOTE/$current"
    fi
}

conditional_rb_pull() {
    sync_remote
    if remote_branch_exists "$working_branch"; then
        info "Branch exists on remote. Syncing..."
        rb_pull_function "$working_branch"
    fi
}
