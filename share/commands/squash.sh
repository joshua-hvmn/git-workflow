# shellcheck shell=bash
# git workflow squash: interactively squash the current branch's own commits
# bin/git-workflow sources this file with the command's arguments in "$@".

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.

. "$GIT_WORKFLOW_DATADIR/core.sh"
. "$GIT_WORKFLOW_DATADIR/release.sh"

# Squash the commits this branch adds on top of the dev branch. --keep-base
# edits those commits in place without moving the branch onto a newer base, so
# a squash never turns into a surprise conflict; `git workflow sync` is for rebasing.
detect_protected_branch "rewrite history"

sync_remote
if [ "$#" -gt 0 ]; then
    squash_against="$1"
else
    # Squash against what this branch was started from: its type's `from`
    # (in git flow, hotfixes from main and everything else from dev)
    squash_base="$DEV_BRANCH"
    squash_type=$(branch_type "$working_branch")
    if [ -n "$squash_type" ] && type_get "$squash_type"; then
        case "$T_FROM" in
        latest-release) squash_base=$(latest_stable_tag) ;;
        *) squash_base=$(resolve_point "$T_FROM") ;;
        esac
    fi
    squash_against="$squash_base"
    # Prefer the fresh remote ref: a stale local copy would list commits
    # that are already merged upstream.
    if [ -n "$squash_base" ] && remote_branch_exists "$squash_base"; then
        squash_against=$(remote_ref "$squash_base")
    fi
fi

git rebase -i --keep-base "$squash_against"

if [ -n "$working_branch" ] && history_rewritten "$working_branch"; then
    note "'$working_branch' was already pushed. Publish the squash with: $(wf_cmd push force)"
fi
