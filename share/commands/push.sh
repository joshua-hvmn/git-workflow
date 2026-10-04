#!/usr/bin/env bash

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.

set -eu

# Where lib/ lives. `make install` fills in this line with the installed path;
# in a checkout (or a `make link` install) lib/ sits next to the real script.
GIT_WORKFLOW_LIBDIR=
if [ -z "$GIT_WORKFLOW_LIBDIR" ]; then
    GIT_WORKFLOW_LIBDIR=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/lib
fi
. "$GIT_WORKFLOW_LIBDIR/git-core-utils.sh"

require_branch
PS_MODE="default"
case "${1:-}" in
force | -f | -F | --force | --force-with-lease)
    PS_MODE="force"
    shift
    ;;
-u)
    shift
    ;;
esac
if [ "$#" -gt 0 ]; then
    err "unexpected argument '$1'. usage: git ps [force]"
    exit 1
fi

case $PS_MODE in
default)
    detect_protected_branch "push"
    sync_remote
    if history_rewritten "$working_branch"; then
        err "'$working_branch' was rewritten (git sq, rebase, or amend) after it was pushed."
        info "Syncing would replay the old commits on top. Publish the rewrite with: git ps force"
        exit 1
    fi
    conditional_rb_pull
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
