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
git fetch --all --prune --tags
__SYNCED=1 # already fetched, stops pull_branch from fetching again
pull_branch "$@"
