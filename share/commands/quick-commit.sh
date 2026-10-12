# shellcheck shell=bash
# git workflow quick-commit: commit, sync with the remote branch, and optionally push
# bin/git-workflow sources this file with the command's arguments in "$@".

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.

. "$GIT_WORKFLOW_DATADIR/core.sh"

push_after=""
case "${1:-}" in
p | -p | --push)
    push_after="p"
    shift
    ;;
esac

[ "$push_after" = "p" ] && require_branch
detect_protected_branch "commit"
commit_changes "$@"
pull_current_branch

if [ "$push_after" = "p" ]; then
    git push -u "$REMOTE" "$working_branch"
fi
