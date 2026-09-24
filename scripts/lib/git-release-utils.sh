#!/bin/bash

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.
#
# Version / tag helpers and the `git b prerelease` command.

# Include guard to prevent redundant parsing
if [ -n "${__RELEASE_UTILS_LOADED:-}" ]; then
    return 0
fi
__RELEASE_UTILS_LOADED=1

if [ -z "${__CORE_UTILS_LOADED:-}" ]; then
    . "$GIT_SCRIPTS_HOME_DIR/lib/git-core-utils.sh"
fi

# ---------------------------------------------------------------------------
# Version helpers (SemVer with a leading "v": v1.2.3, v1.2.3-rc.1)
# ---------------------------------------------------------------------------

# vX.Y.Z only
is_stable_version() {
    [[ "$1" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}

# vX.Y.Z-<dot separated identifiers>
is_prerelease_version() {
    [[ "$1" =~ ^v(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*$ ]]
}

# version_gt A B -> true if A > B (stable versions only)
version_gt() {
    [ "$1" != "$2" ] && [ "$(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n 1)" = "$1" ]
}

latest_stable_tag() {
    local t
    for t in $(git tag --list 'v*' --sort=-v:refname); do
        if is_stable_version "$t"; then
            printf '%s' "$t"
            return 0
        fi
    done
}

# Local check; remote tags are already here after sync_remote (fetch --tags).
tag_exists() {
    git show-ref --verify --quiet "refs/tags/$1"
}

# release/v1.2.3 -> v1.2.3 (empty if the branch is not a release/hotfix branch)
branch_version() {
    case "$1" in
    "$RELEASE_PREFIX"*) printf '%s' "${1#"$RELEASE_PREFIX"}" ;;
    "$HOTFIX_PREFIX"*) printf '%s' "${1#"$HOTFIX_PREFIX"}" ;;
    esac
}

prerelease_tags_for() {
    git tag --list "$1-*" --sort=v:refname
}

# next_prerelease_tag v1.2.3 rc -> v1.2.3-rc.<highest existing + 1>
next_prerelease_tag() {
    local base="$1" label="$2" t n max=0
    for t in $(git tag --list "$base-$label.*"); do
        n="${t##*.}"
        case "$n" in
        '' | *[!0-9]*) continue ;;
        esac
        [ "$n" -gt "$max" ] && max="$n"
    done
    printf '%s-%s.%d' "$base" "$label" "$((10#$max + 1))"
}

# Validate a new release/hotfix version before a branch is started or finished.
validate_new_version() {
    local version="$1" latest

    if ! is_stable_version "$version"; then
        flow_warn "'$version' is not a SemVer version (expected vX.Y.Z)." || return 1
        return 0
    fi
    if tag_exists "$version"; then
        err "tag '$version' already exists."
        return 1
    fi
    latest=$(latest_stable_tag)
    if [ -n "$latest" ] && ! version_gt "$version" "$latest"; then
        flow_warn "'$version' is not newer than the latest release '$latest'." || return 1
    fi
}

# GitHub Actions URL for the remote, if it is a GitHub remote
actions_url() {
    local url
    url=$(git remote get-url "$REMOTE" 2>/dev/null) || return 0
    url="${url%.git}"
    case "$url" in
    git@github.com:*) printf 'https://github.com/%s/actions' "${url#git@github.com:}" ;;
    ssh://git@github.com/*) printf 'https://github.com/%s/actions' "${url#ssh://git@github.com/}" ;;
    https://github.com/*) printf '%s/actions' "$url" ;;
    esac
}

# Push local commits so the tagged commit also lives on the remote branch.
ensure_branch_pushed() {
    local branch="$1" counts ahead behind

    if ! remote_branch_exists "$branch"; then
        if yes_no "'$branch' is not on '$REMOTE' yet. Push it now?" "y"; then
            git push -u "$REMOTE" "$branch" || return 1
            return 0
        fi
        flow_warn "the prerelease will point at a commit that is on no remote branch." || return 1
        return 0
    fi

    counts=$(git rev-list --left-right --count "HEAD...$REMOTE/$branch") || return 1
    ahead="${counts%%[[:space:]]*}"
    behind="${counts##*[[:space:]]}"

    if [ "$behind" -gt 0 ]; then
        err "'$branch' is $behind commit(s) behind '$REMOTE/$branch'. Run 'git sync' first."
        return 1
    fi
    if [ "$ahead" -gt 0 ]; then
        if yes_no "Push $ahead local commit(s) to '$REMOTE/$branch' first?" "y"; then
            git push "$REMOTE" "$branch" || return 1
        else
            flow_warn "the prerelease will include commits that are not on '$REMOTE/$branch'." || return 1
        fi
    fi
}

prerelease_usage() {
    cat >&2 <<EOF
usage: git b prerelease [label | full-tag] [-n|--dry-run] [-l|--list]

Tag HEAD of the current release/hotfix branch as a prerelease and push the tag,
which triggers the release workflow (published as a GitHub prerelease).

  git b pre              -> v1.2.3-$PRERELEASE_LABEL.N  (N = next free number)
  git b pre beta         -> v1.2.3-beta.N
  git b pre v1.2.3-rc.7  -> exactly that tag
  git b pre -n           -> show the tag that would be created, change nothing
  git b pre -l           -> list prerelease tags for this branch's version
EOF
}

prerelease_branch() {
    local mode="create" arg="" branch="$working_branch"
    local base tag label latest sha existing url

    while [ "$#" -gt 0 ]; do
        case "$1" in
        -n | --dry-run) mode="dry" ;;
        -l | --list) mode="list" ;;
        -h | --help)
            prerelease_usage
            return 0
            ;;
        -*)
            err "unknown option: $1"
            prerelease_usage
            return 1
            ;;
        *)
            if [ -n "$arg" ]; then
                err "too many arguments."
                prerelease_usage
                return 1
            fi
            arg="$1"
            ;;
        esac
        shift
    done

    if [ -z "$branch" ]; then
        err "not on a branch (detached HEAD)."
        return 1
    fi

    base=$(branch_version "$branch")
    if [ -z "$base" ]; then
        flow_warn "prereleases are cut from '${RELEASE_PREFIX}*' or '${HOTFIX_PREFIX}*' branches; '$branch' is neither." || return 1
    elif ! is_stable_version "$base"; then
        flow_warn "branch version '$base' is not vX.Y.Z; cannot derive a prerelease tag from it." || return 1
        base=""
    fi

    sync_remote

    if [ "$mode" = "list" ]; then
        if [ -z "$base" ]; then
            err "cannot list prereleases: no version in branch name '$branch'."
            return 1
        fi
        prerelease_tags_for "$base"
        return 0
    fi

    # Work out the tag
    if is_prerelease_version "$arg"; then
        tag="$arg"
        if [ -n "$base" ] && [ "${tag%%-*}" != "$base" ]; then
            flow_warn "'$tag' does not match this branch's version '$base'." || return 1
        fi
        base="${tag%%-*}"
    else
        label="${arg:-$PRERELEASE_LABEL}"
        if ! [[ "$label" =~ ^[0-9A-Za-z-]+$ ]]; then
            err "invalid prerelease label '$label' (letters, digits and '-' only), or pass a full tag like v1.2.3-rc.1."
            return 1
        fi
        if [ -z "$base" ]; then
            err "no version in branch name; pass a full tag instead, e.g. 'git b pre v1.2.3-rc.1'."
            return 1
        fi
        tag=$(next_prerelease_tag "$base" "$label")
    fi

    # Sanity checks
    if tag_exists "$tag"; then
        err "tag '$tag' already exists."
        return 1
    fi
    if tag_exists "$base"; then
        err "'$base' has already been released; a '$tag' prerelease would sort before it."
        return 1
    fi
    latest=$(latest_stable_tag)
    if [ -n "$latest" ] && ! version_gt "$base" "$latest"; then
        flow_warn "'$base' is not newer than the latest release '$latest'." || return 1
    fi

    sha=$(git rev-parse --short HEAD)

    if [ "$mode" = "dry" ]; then
        info "Would tag $sha ($(git log -1 --format=%s HEAD)) as '$tag' and push it to '$REMOTE'."
        existing=$(prerelease_tags_for "$base" | tr '\n' ' ')
        [ -n "$existing" ] && info "Existing prereleases for $base: $existing"
        return 0
    fi

    if ! git diff --quiet HEAD -- 2>/dev/null; then
        flow_warn "you have uncommitted changes; they will NOT be in '$tag'." || return 1
    fi

    ensure_branch_pushed "$branch" || return 1

    if ! yes_no "Create prerelease tag '$tag' at $sha and push it (triggers the release workflow)?"; then
        info "Aborted."
        return 1
    fi

    git tag -a "$tag" -m "prerelease: $tag" || return 1
    if ! git push "$REMOTE" "refs/tags/$tag"; then
        git tag -d "$tag" >/dev/null
        err "push failed; removed local tag '$tag'."
        return 1
    fi

    note "Pushed prerelease '$tag'."
    url=$(actions_url)
    [ -n "$url" ] && note "Watch the release run: $url  (or: gh run watch)"
    return 0
}
