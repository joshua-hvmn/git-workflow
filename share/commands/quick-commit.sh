# shellcheck shell=bash
# git workflow quick-commit: commit, sync with the remote branch, and optionally push
# bin/git-workflow sources this file with the command's arguments in "$@".

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.

. "$GIT_WORKFLOW_DATADIR/core.sh"

QC_MODE=""
case "${1:-}" in
p | -p | --push)
    QC_MODE="p"
    shift
    ;;
esac

[ "$QC_MODE" = "p" ] && require_branch
detect_protected_branch "commit"
commit_function "$@"
conditional_rb_pull

if [ "$QC_MODE" = "p" ]; then
    git push -u "$REMOTE" "$working_branch"
fi
