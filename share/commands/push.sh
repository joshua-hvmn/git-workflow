# shellcheck shell=bash
# git workflow push: sync with the remote branch, then push
# bin/git-workflow sources this file with the command's arguments in "$@".

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.

. "$GIT_WORKFLOW_DATADIR/core.sh"

require_branch
push_mode="default"
case "${1:-}" in
force | -f | -F | --force | --force-with-lease)
    push_mode="force"
    shift
    ;;
-u)
    shift
    ;;
esac
if [ "$#" -gt 0 ]; then
    err "unexpected argument '$1'. usage: $(wf_cmd push "[force]")"
    exit 1
fi

case $push_mode in
default)
    detect_protected_branch "push"
    sync_remote
    if history_rewritten "$working_branch"; then
        err "'$working_branch' was rewritten (squash, rebase, or amend) after it was pushed."
        info "Syncing would replay the old commits on top. Publish the rewrite with: $(wf_cmd push force)"
        exit 1
    fi
    pull_current_branch
    git push -u "$REMOTE" "$working_branch"
    ;;
force)
    if is_protected_branch "$working_branch"; then # need a way to force it anywhere
        err "refusing to force-push protected branch '$working_branch'."
        exit 1
    fi
    git push --force-with-lease --force-if-includes -u "$REMOTE" "$working_branch"
    ;;
esac
