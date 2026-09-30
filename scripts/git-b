#!/usr/bin/env bash

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.

set -eu
[ "$#" -eq 0 ] && exec git --no-pager branch

# Where lib/ lives. `make install` fills in this line with the installed path;
# in a checkout (or a `make link` install) lib/ sits next to the real script.
GIT_WORKFLOW_LIBDIR=
if [ -z "$GIT_WORKFLOW_LIBDIR" ]; then
    GIT_WORKFLOW_LIBDIR=$(dirname -- "$(readlink -f -- "${BASH_SOURCE[0]}")")/lib
fi
# Source util script
. "$GIT_WORKFLOW_LIBDIR/git-core-utils.sh"
. "$GIT_WORKFLOW_LIBDIR/git-release-utils.sh"
. "$GIT_WORKFLOW_LIBDIR/git-branch-utils.sh"

b_usage() {
    cat >&2 <<EOF
usage: git b [<subcommand>] [args]

  start <topic|release|hotfix> [name]   start a branch (release/hotfix name = vX.Y.Z)
  prerelease|pre [label|tag] [-n] [-l]  tag the release branch as vX.Y.Z-<label>.N and push
  finish [branch]                       merge per the flow, tag releases/hotfixes, push
  delete [branch] [-y] [-f]             delete a branch locally and on the remote (-f: even if unmerged)
  config                                show the effective workflow settings
  help                                  this message
  version                               show the git-workflow version

Anything else is passed to 'git branch' (e.g. 'git b -a', 'git b -vv').
Settings and guardrails: man git-workflow
EOF
}

B_SUBCMD="${1:-}"
shift

case "$B_SUBCMD" in
start)
    start_branch "$@"
    ;;
finish)
    finish_branch "$@"
    ;;
delete)
    delete_branch "$@"
    ;;
prerelease | pre)
    prerelease_branch "$@"
    ;;
config)
    show_config
    ;;
help | --help | -h)
    b_usage
    ;;
version | --version | -V)
    # Installed: next to the libraries. Checkout: at the repo root.
    b_version=unknown
    for f in "$GIT_WORKFLOW_LIBDIR/VERSION" "$GIT_WORKFLOW_LIBDIR/../../VERSION"; do
        if [ -r "$f" ]; then
            b_version=$(cat "$f")
            break
        fi
    done
    printf 'git-workflow %s\n' "$b_version"
    ;;
*)
    exec git branch "$B_SUBCMD" "$@"
    ;;
esac
