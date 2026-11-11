# shellcheck shell=bash
# git-workflow forge: GitLab, through the GitLab CLI (glab) and jq.
#
# The same functions as share/forges/github.sh, which describes them. GitLab
# calls pull requests merge requests; messages keep git-workflow's word.
#
# Merge requests go to UPSTREAM's project. One from your fork names the fork
# as its head project (glab mr create --head), and when looking one up, only
# merge requests whose source project is that fork count.

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman

forge_name() {
    printf 'GitLab CLI (glab)'
}

forge_require() {
    local missing=""
    command -v glab >/dev/null 2>&1 || missing="the GitLab CLI (glab, https://gitlab.com/gitlab-org/cli)"
    command -v jq >/dev/null 2>&1 || missing="${missing:+$missing and }jq"
    [ -z "$missing" ] && return 0
    err "opening merge requests on GitLab needs $missing, and it isn't installed."
    info "Install it, or merge locally: git config workflow.integrate merge"
    return 1
}

# The project a remote points at, as a URL glab takes for -R and --head
# (https://gitlab.com/group/sub/repo); empty when its URL doesn't say
__gl_project() {
    local slug
    slug=$(remote_slug "$1")
    if [ -n "$slug" ]; then
        printf 'https://%s' "$slug"
    fi
}

# The numeric ID of the project <remote> points at, if GitLab will say
__gl_project_id() {
    local slug host path
    slug=$(remote_slug "$1")
    [ -n "$slug" ] || return 0
    host="${slug%%/*}" path="${slug#*/}"
    glab api --hostname "$host" "projects/${path//\//%2F}" 2>/dev/null | jq -r '.id // empty' 2>/dev/null || :
}

# jq that picks the newest merge request whose source is <remote>'s project:
# the target project itself, or your fork
__gl_pick() {
    local id
    if [ "$1" = "$UPSTREAM" ]; then
        printf 'map(select(.source_project_id == .target_project_id)) | .[0]'
        return 0
    fi
    id=$(__gl_project_id "$1")
    case "$id" in
    '' | *[!0-9]*) printf '.[0]' ;;
    *) printf 'map(select(.source_project_id == %s)) | .[0]' "$id" ;;
    esac
}

# __gl_list <branch> <remote> <state flag> <jq for the picked one> [<target>]
__gl_list() {
    local repo out
    repo=$(__gl_project "$UPSTREAM")
    # Not a pipe: a failing glab must fail here, not hand jq nothing
    out=$(glab mr list ${repo:+-R "$repo"} "$3" -s "$1" ${5:+-t "$5"} -o created_at -S desc -P 30 -F json) || return 1
    printf '%s' "$out" | jq -r "$(__gl_pick "$2") | if . == null then empty else $4 end"
}

forge_pr_find() {
    __gl_list "$1" "$2" --all \
        '(if .state == "opened" then "OPEN" elif .state == "merged" then "MERGED" else "CLOSED" end) + " " + .web_url' \
        "${3:-}"
}

# A merge commit, or with squash and fast-forward merges, the squashed (or
# rebased) commit; finish checks it's on the target before tagging it
forge_pr_merge_commit() {
    __gl_list "$1" "$2" --merged '(.merge_commit_sha // .squash_commit_sha // .sha)'
}

forge_pr_head() {
    __gl_list "$1" "$2" --merged '.sha'
}

forge_pr_create() {
    local base="$1" branch="$2" remote="$3" title="$4" body="$5" repo head=""
    repo=$(__gl_project "$UPSTREAM")
    if [ "$remote" != "$UPSTREAM" ]; then
        head=$(__gl_project "$remote")
    fi
    # The branch is pushed already; --push=false keeps --fill from pushing it again
    if [ -n "$title" ]; then
        glab mr create -s "$branch" -b "$base" ${head:+--head "$head"} -t "$title" -d "$body" \
            -y --push=false ${repo:+-R "$repo"}
    else
        glab mr create -s "$branch" -b "$base" ${head:+--head "$head"} --fill \
            -y --push=false ${repo:+-R "$repo"}
    fi
}

# Pipelines for the project the tags go to
forge_ci_hint() {
    local repo
    repo=$(__gl_project "$UPSTREAM")
    if [ -n "$repo" ]; then
        printf '%s/-/pipelines  (or: glab ci view)' "$repo"
    fi
}
