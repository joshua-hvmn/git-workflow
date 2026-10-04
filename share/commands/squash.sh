# shellcheck shell=bash
# git workflow squash: interactively squash the current branch's own commits
# bin/git-workflow sources this file with the command's arguments in "$@".

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.

. "$GIT_WORKFLOW_DATADIR/core.sh"

# Squash the commits this branch adds on top of the dev branch. --keep-base
# edits those commits in place without moving the branch onto a newer base, so
# a squash never turns into a surprise conflict; `git sync` is for rebasing.
detect_protected_branch "rewrite history"

sync_remote
if [ "$#" -gt 0 ]; then
    squash_against="$1"
else
    # squash against the branch this one was started from: hotfixes come from main, everything
    # else from dev.
    squash_base="$DEV_BRANCH"
    case "$working_branch" in
    "$HOTFIX_PREFIX"*) squash_base="$MAIN_BRANCH" ;;
    esac
    squash_against="$squash_base"
    # Prefer the fresh remote ref: a stale local copy would list commits
    # that are already merged upstream.
    if remote_branch_exists "$squash_base"; then
        squash_against="$REMOTE/$squash_base"
    fi
fi

git rebase -i --keep-base "$squash_against"

if [ -n "$working_branch" ] && history_rewritten "$working_branch"; then
    note "'$working_branch' was already pushed. Publish the squash with: $(wf_cmd push force)"
fi
