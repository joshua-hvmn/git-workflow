# shellcheck shell=bash
# git workflow sync: fetch everything, then bring a branch up to date
# bin/git-workflow sources this file with the command's arguments in "$@".

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.

. "$GIT_WORKFLOW_DATADIR/core.sh"

# MAIN
info "Fetching all remotes and pruning dead branches..."
if [ "$REMOTE" = "$UPSTREAM" ]; then
    git fetch --all --prune --tags
else
    # Tags come from UPSTREAM, as in sync_remote: a fork's copies may differ
    git fetch --all --prune --no-tags
    git fetch --prune --tags "$UPSTREAM"
fi
__SYNCED=1 # already fetched, stops pull_branch from fetching again
pull_branch "$@"
