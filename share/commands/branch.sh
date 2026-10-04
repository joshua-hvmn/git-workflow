# shellcheck shell=bash
# git workflow branch: start, prerelease, finish and delete branches; anything else goes to git branch
# bin/git-workflow sources this file with the command's arguments in "$@".

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.

[ "$#" -eq 0 ] && exec git --no-pager branch

. "$GIT_WORKFLOW_DATADIR/core.sh"
. "$GIT_WORKFLOW_DATADIR/release.sh"
. "$GIT_WORKFLOW_DATADIR/flow.sh"

branch_usage() {
    local b
    b=$(wf_cmd branch)
    cat >&2 <<EOF
usage: $b [<subcommand>] [args]

  start <topic|release|hotfix> [name]   start a branch (release/hotfix name = vX.Y.Z)
  prerelease|pre [label|tag] [-n] [-l]  tag the release branch as vX.Y.Z-<label>.N and push
  finish [branch]                       merge per the flow, tag releases/hotfixes, push
  delete [branch] [-y] [-f]             delete a branch locally and on the remote (-f: even if unmerged)
  config                                show the effective workflow settings
  help                                  this message
  version                               show the git-workflow version

Anything else is passed to 'git branch' (e.g. '$b -a', '$b -vv').
Manual: git workflow help branch
EOF
}

subcommand="$1"
shift

case "$subcommand" in
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
    printf 'git-workflow %s\n' "$(wf_version)"
    ;;
*)
    exec git branch "$subcommand" "$@"
    ;;
esac
