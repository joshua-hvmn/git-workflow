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
