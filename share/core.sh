# shellcheck shell=bash
# Sourced by every git-workflow command; not executable on its own.

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
# Commands and the aliases that run them
# ---------------------------------------------------------------------------

# wf_resolve <name>: the command a name runs, short (1.x) names included.
# Prints nothing and fails for anything else.
wf_resolve() {
    case "$1" in
    branch | b) echo branch ;;
    commit | c) echo commit ;;
    quick-commit | qc) echo quick-commit ;;
    push | ps) echo push ;;
    squash | sq) echo squash ;;
    sync) echo sync ;;
    pull | rb-pull) echo pull ;;
    aliases) echo aliases ;;
    *) return 1 ;;
    esac
}

# Record an alias whose whole value is "workflow <command>"
__wf_note_alias() {
    local name="$1" w1 w2 rest cmd
    read -r w1 w2 rest <<<"$2"
    [ "$w1" = workflow ] && [ -n "$w2" ] && [ -z "$rest" ] || return 0
    cmd=$(wf_resolve "$w2") || return 0
    WF_ALIASES="$WF_ALIASES$cmd $name
"
}

# wf_alias_for <command>: the first alias that runs it, if any
wf_alias_for() {
    local cmd name
    while read -r cmd name; do
        if [ "$cmd" = "$1" ]; then
            printf '%s' "$name"
            return 0
        fi
    done <<<"$WF_ALIASES"
    return 1
}

# wf_cmd <command> [args...]: how to type a command, for messages. Uses your
# alias when you have one ("git ps force"), the full form otherwise
# ("git workflow push force").
wf_cmd() {
    local cmd="$1" name
    shift
    if name=$(wf_alias_for "$cmd"); then
        set -- "git $name" "$@"
    else
        set -- "git workflow $cmd" "$@"
    fi
    printf '%s' "$*"
}

# The installed version: next to the libraries when installed, at the root of
# a checkout otherwise
wf_version() {
    local f
    for f in "$GIT_WORKFLOW_DATADIR/VERSION" "$GIT_WORKFLOW_DATADIR/../VERSION"; do
        if [ -r "$f" ]; then
            cat "$f"
            return 0
        fi
    done
    echo unknown
}

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
#   git config workflow.finishTopic     merge     # merge | pr (open a pull request with gh instead)
#   git config workflow.versionFile     VERSION   # must match the tag in pre/finish; "" disables
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
FINISH_TOPIC=merge
VERSION_FILE=VERSION
EXTRA_PROTECTED=''
# "<command> <alias>" lines, one per alias that runs a git-workflow command
# ("b = workflow branch"), so messages can name commands the way you type them
WF_ALIASES=''

while read -r __key __value; do
    case "$__key" in
    alias.*) __wf_note_alias "${__key#alias.}" "$__value" ;;
    workflow.mainbranch) MAIN_BRANCH="$__value" ;;
    workflow.devbranch) DEV_BRANCH="$__value" ;;
    workflow.remote) REMOTE="$__value" ;;
    workflow.releaseprefix) RELEASE_PREFIX="$__value" ;;
    workflow.hotfixprefix) HOTFIX_PREFIX="$__value" ;;
    workflow.prereleaselabel) PRERELEASE_LABEL="$__value" ;;
    workflow.protected) EXTRA_PROTECTED="$EXTRA_PROTECTED $__value" ;;
    workflow.finishtopic) FINISH_TOPIC="$__value" ;;
    workflow.versionfile) VERSION_FILE="$__value" ;;
    workflow.strict)
        # A bare `strict` with no value means true, same as git's own booleans
        case "$__value" in
        '' | [Tt][Rr][Uu][Ee] | [Yy][Ee][Ss] | [Oo][Nn] | 1) STRICT=true ;;
        *) STRICT=false ;;
        esac
        ;;
    esac
done < <(git config --get-regexp '^(workflow|alias)\.' 2>/dev/null || true)
unset __key __value

case "$FINISH_TOPIC" in
merge | pr) ;;
*)
    warn "workflow.finishTopic must be 'merge' or 'pr', not '$FINISH_TOPIC'; using 'merge'."
    FINISH_TOPIC=merge
    ;;
esac

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
# commit_function [--amend] [--] [message words...]
# The message is plain words, so anything else starting with "-" is almost
# certainly a `git commit` flag typed from habit: `git c -m "fix"` would
# otherwise commit the message "-m fix". Put -- before a message that really
# starts with a dash.
commit_function() {
    local amend=""

    if [ "${1:-}" = "--amend" ]; then
        amend=1
        shift
    fi
    if [ "${1:-}" = "--" ]; then
        shift
    else
        case "${1:-}" in
        -*)
            err "unknown option '$1'. The message is plain words: $(wf_cmd commit fix the bug), or $(wf_cmd quick-commit "'fix the bug'")"
            info "(use --): $(wf_cmd commit "[--amend] -- $1")"
            return 1
            ;;
        esac
    fi

    if [ -n "$amend" ]; then
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
        git merge-base --is-ancestor "refs/remotes/$REMOTE/$current" "refs/heads/$current" && return 0
        if history_rewritten "$current"; then
            err "'$current' was rewritten after it was pushed."
            info "Pulling would replay the old commits on top. Publish the rewrite first: git ps force"
            return 1
        fi
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

# True when <branch> has diverged from its remote copy only because it was
# rewritten locally (git sq, rebase, amend) after being pushed: the remote tip
# is a commit this branch pointed at before, according to its reflog. Pulling
# would then replay the old commits on top of the rewritten ones.
# (This is the same test `git push --force-if-includes` uses.)
history_rewritten() {
    local branch="$1" tip entries

    remote_branch_exists "$branch" || return 1
    tip=$(git rev-parse "refs/remotes/$REMOTE/$branch") || return 1
    # Remote is behind or equal: an ordinary push
    git merge-base --is-ancestor "$tip" "refs/heads/$branch" && return 1

    entries=$(git rev-list --walk-reflogs --max-count=200 "refs/heads/$branch" 2>/dev/null) || return 1
    [ -n "$entries" ] || return 1
    # Prints the tip if no reflog entry contains it
    # shellcheck disable=SC2086
    [ -z "$(git rev-list --max-count=1 "$tip" --not $entries)" ]
}
