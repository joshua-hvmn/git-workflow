# shellcheck shell=bash
# git-workflow forge: GitHub, through the GitHub CLI (gh).
#
# A forge is how git-workflow opens and looks up pull requests. flow.sh loads
# share/forges/<workflow.forge>.sh when it needs one, and calls only these:
#
#   forge_name                        what to call it in messages
#   forge_require                     fail, saying what to install, if it can't work here
#   forge_pr_find <branch> <remote>   "<OPEN|MERGED|CLOSED> <url>" of the newest pull
#                                     request from <branch> (pushed to <remote>) into
#                                     UPSTREAM; nothing if there's none
#   forge_pr_merge_commit <branch> <remote>
#                                     the commit that merged it (merge, squash or rebase)
#   forge_pr_create <base> <branch> <remote> <title> <body>
#                                     open one into <base>; an empty title fills the
#                                     title and body from the commits
#
# Pull requests always go to UPSTREAM's repository. A branch on another remote
# (your fork) is <fork owner>:<branch> there. Another forge (GitLab's glab, say)
# is another file with these five functions.

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman

forge_name() {
    printf 'GitHub CLI (gh)'
}

forge_require() {
    command -v gh >/dev/null 2>&1 && return 0
    err "opening pull requests needs the GitHub CLI (gh), and it isn't installed."
    info "Install it (https://cli.github.com), or merge locally: git config workflow.integrate merge"
    return 1
}

# UPSTREAM's repository (owner/name), when its URL says which one it is; used
# as ${GH_REPO:+--repo "$GH_REPO"} (an empty array would trip set -u in Bash 3.2)
__gh_repo() {
    GH_REPO=$(remote_slug "$UPSTREAM")
}

# The owner of the repository <remote> points at, if it's a plain GitHub name
__gh_owner() {
    local slug owner
    slug=$(remote_slug "$1")
    owner="${slug%%/*}"
    case "$owner" in
    '' | *[!A-Za-z0-9-]*) return 0 ;;
    esac
    printf '%s' "$owner"
}

# jq that picks the newest pull request whose head is on <remote>'s repository
__gh_pick() {
    local owner
    owner=$(__gh_owner "$1")
    if [ -n "$owner" ]; then
        printf 'map(select(.headRepositoryOwner.login == "%s")) | .[0]' "$owner"
    else
        printf '.[0]'
    fi
}

forge_pr_find() {
    __gh_repo
    gh pr list ${GH_REPO:+--repo "$GH_REPO"} --head "$1" --state all --limit 30 \
        --json state,url,headRepositoryOwner \
        --jq "$(__gh_pick "$2") | if . == null then empty else .state + \" \" + .url end" 2>/dev/null || true
}

forge_pr_merge_commit() {
    __gh_repo
    gh pr list ${GH_REPO:+--repo "$GH_REPO"} --head "$1" --state merged --limit 30 \
        --json mergeCommit,headRepositoryOwner \
        --jq "$(__gh_pick "$2") | if . == null then empty else .mergeCommit.oid end" 2>/dev/null || true
}

forge_pr_create() {
    local base="$1" branch="$2" remote="$3" title="$4" body="$5" head owner
    head="$branch"
    if [ "$remote" != "$UPSTREAM" ]; then
        owner=$(__gh_owner "$remote")
        [ -n "$owner" ] && head="$owner:$branch"
    fi
    __gh_repo
    if [ -n "$title" ]; then
        gh pr create --base "$base" --head "$head" --title "$title" --body "$body" ${GH_REPO:+--repo "$GH_REPO"}
    else
        gh pr create --base "$base" --head "$head" --fill ${GH_REPO:+--repo "$GH_REPO"}
    fi
}
