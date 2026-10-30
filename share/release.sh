# shellcheck shell=bash
# Sourced by the git-workflow commands; not executable on its own.

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.
#
# Version / tag helpers, and the `git workflow branch prerelease` and
# `git workflow branch release` commands.

# Include guard to prevent redundant parsing
if [ -n "${__WF_RELEASE_LOADED:-}" ]; then
    return 0
fi
__WF_RELEASE_LOADED=1

if [ -z "${__WF_CORE_LOADED:-}" ]; then
    . "$GIT_WORKFLOW_DATADIR/core.sh"
fi

# ---------------------------------------------------------------------------
# Version helpers. A version is SemVer after workflow.tagPrefix (TAG_PREFIX,
# default "v"): v1.2.3, v1.2.3-rc.1; with tagPrefix "", 1.2.3.
# ---------------------------------------------------------------------------

# The SemVer part: X.Y.Z, and X.Y.Z-<dot separated identifiers>
__is_semver() {
    [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)$ ]]
}
__is_semver_pre() {
    [[ "$1" =~ ^(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)\.(0|[1-9][0-9]*)-[0-9A-Za-z-]+(\.[0-9A-Za-z-]+)*$ ]]
}

# <tagPrefix>X.Y.Z only
is_stable_version() {
    case "$1" in
    "$TAG_PREFIX"*) __is_semver "${1#"$TAG_PREFIX"}" ;;
    *) return 1 ;;
    esac
}

# <tagPrefix>X.Y.Z-<dot separated identifiers>
is_prerelease_version() {
    case "$1" in
    "$TAG_PREFIX"*) __is_semver_pre "${1#"$TAG_PREFIX"}" ;;
    *) return 1 ;;
    esac
}

# version_base v1.2.3-rc.1 -> v1.2.3 (a tag prefix may contain "-" itself)
version_base() {
    local rest="${1#"$TAG_PREFIX"}"
    printf '%s%s' "$TAG_PREFIX" "${rest%%-*}"
}

# normalize_version <word>: a version typed without the tag prefix, or with
# a "v" the prefix doesn't have, as this repository's tags spell it (1.2.3 ->
# v1.2.3). Anything else comes back unchanged.
normalize_version() {
    local core="${1#v}"
    if is_stable_version "$1" || is_prerelease_version "$1"; then
        printf '%s' "$1"
    elif __is_semver "$1" || __is_semver_pre "$1"; then
        printf '%s%s' "$TAG_PREFIX" "$1"
    elif __is_semver "$core" || __is_semver_pre "$core"; then
        printf '%s%s' "$TAG_PREFIX" "$core"
    else
        printf '%s' "$1"
    fi
}

# bump_version <major|minor|patch>: the next version after the latest
# release (after 0.0.0 when there's none)
bump_version() {
    local latest x y z
    latest=$(latest_stable_tag)
    latest="${latest#"$TAG_PREFIX"}"
    latest="${latest:-0.0.0}"
    x="${latest%%.*}" z="${latest##*.}" y="${latest#*.}" y="${y%.*}"
    case "$1" in
    major) x=$((x + 1)) y=0 z=0 ;;
    minor) y=$((y + 1)) z=0 ;;
    patch) z=$((z + 1)) ;;
    *) return 1 ;;
    esac
    printf '%s%d.%d.%d' "$TAG_PREFIX" "$x" "$y" "$z"
}

# version_gt A B -> true if A > B. Both must be stable versions (callers
# validate first). MacOS/BSD compatible sort instead of sort -V
version_gt() {
    local a="${1#"$TAG_PREFIX"}" b="${2#"$TAG_PREFIX"}" a1 a2 a3 b1 b2 b3
    a1=${a%%.*} a3=${a##*.} a2=${a#*.} a2=${a2%.*}
    b1=${b%%.*} b3=${b##*.} b2=${b#*.} b2=${b2%.*}
    if [ "$a1" -ne "$b1" ]; then return $((a1 > b1 ? 0 : 1)); fi
    if [ "$a2" -ne "$b2" ]; then return $((a2 > b2 ? 0 : 1)); fi
    return $((a3 > b3 ? 0 : 1))
}

latest_stable_tag() {
    local t
    for t in $(git tag --list "$TAG_PREFIX*" --sort=-v:refname); do
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

# not_released <rev>: fail, saying so, when <rev> already carries a release tag
# (a versioned branch with no commits of its own would tag the last release again)
not_released() {
    local t
    for t in $(git tag --points-at "$1"); do
        if is_stable_version "$t"; then
            err "$(git rev-parse --short "$1") is already released as $t; there's nothing new to tag."
            return 1
        fi
    done
}

# release/v1.2.3 -> v1.2.3: the name after the prefix, for a branch of a
# versioned type (one that finishes with a tag); empty for any other branch
branch_version() {
    local t
    t=$(branch_type "$1")
    [ -n "$t" ] && type_versioned "$t" || return 0
    printf '%s' "${1#"$T_PREFIX"}"
}

# "'release/*' or 'hotfix/*'": the branches prereleases can be cut from
versioned_prefixes() {
    local t out=""
    for t in $WF_TYPES; do
        type_versioned "$t" || continue
        [ -n "$out" ] && out="$out or "
        out="$out'$T_PREFIX*'"
    done
    printf '%s' "${out:-(none in this flow)}"
}

# Oldest first, by when they were cut (the last key sorts first), so the last
# one is what was tested last whatever its label: rc.2, then beta.1
prerelease_tags_for() {
    git tag --list "$1-*" --sort=v:refname --sort=creatordate
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
        flow_warn "'$version' is not a SemVer version (expected $VFMT)." || return 1
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

# ---------------------------------------------------------------------------
# The version file (workflow.versionFile). Its name says how to read it:
# package.json (the top-level "version"), Cargo.toml ([package], else
# [workspace.package]), pyproject.toml ([project], else [tool.poetry]).
# Any other file holds just the version, "1.2.3" or "v1.2.3". awk, not jq or
# a TOML parser: nothing to install, and nothing in the file is run.
# ---------------------------------------------------------------------------

version_file_format() {
    case "${VERSION_FILE##*/}" in
    package.json) echo json ;;
    Cargo.toml) echo cargo ;;
    pyproject.toml) echo pyproject ;;
    *) echo plain ;;
    esac
}

# Prints "<line number><TAB><version as written>" for a JSON document's
# top-level "version" string, on stdin; nothing if there isn't one
# shellcheck disable=SC2016 # awk's own $0, not the shell's
__WF_AWK_JSON='
{
    n = length($0)
    for (i = 1; i <= n; i++) {
        c = substr($0, i, 1)
        if (instr) {
            if (c == "\\") { i++; continue }
            if (c != "\"") { str = str c; continue }
            instr = 0
            if (depth == 1 && state == "key") { key = str; state = "colon" }
            else if (depth == 1 && state == "value") {
                if (key == "version") { print NR "\t" str; exit }
                state = "next"
            }
            continue
        }
        if (c == "\"") { instr = 1; str = ""; continue }
        if (c == "{" || c == "[") {
            if (depth == 0 && c == "{") state = "key"
            else if (depth == 1 && state == "value") state = "next"
            depth++
            continue
        }
        if (c == "}" || c == "]") { depth--; continue }
        if (depth != 1) continue
        if (c == ":" && state == "colon") state = "value"
        else if (c == ",") state = "key"
    }
}'

# Prints "<line number><TAB><version>" for the first `version = "..."` in the
# first of the TOML tables named in `tables` that has one
# shellcheck disable=SC2016 # awk's own $0, not the shell's
__WF_AWK_TOML='
BEGIN { n = split(tables, want, " ") }
/^[ \t]*\[/ {
    t = $0
    sub(/^[ \t]*\[+[ \t]*/, "", t)
    sub(/[ \t]*\].*$/, "", t)
    table = t
    next
}
/^[ \t]*version[ \t]*=/ && !(table in found) {
    v = $0
    sub(/^[^=]*=[ \t]*/, "", v)
    q = substr(v, 1, 1)
    if (q != "\"" && q != "\047") next
    v = substr(v, 2)
    v = substr(v, 1, index(v, q) - 1)
    found[table] = NR "\t" v
}
END { for (i = 1; i <= n; i++) if (want[i] in found) { print found[want[i]]; exit } }'

# __version_file_locate: reads the file on stdin, prints "<line><TAB><version>"
__version_file_locate() {
    case "$(version_file_format)" in
    json) awk "$__WF_AWK_JSON" ;;
    cargo) awk -v tables="package workspace.package" "$__WF_AWK_TOML" ;;
    pyproject) awk -v tables="project tool.poetry" "$__WF_AWK_TOML" ;;
    *) awk 'NF { gsub(/[ \t\r]/, ""); print NR "\t" $0; exit }' ;;
    esac
}

# version_file_raw <rev>: the version as the file at <rev> writes it ("1.2.3",
# "v1.2.3"). Fails when there's no version file, or (for package.json and the
# TOML files) when it has no version of its own (setuptools-scm, say).
version_file_raw() {
    local content found
    [ -n "$VERSION_FILE" ] || return 1
    content=$(git show "$1:$VERSION_FILE" 2>/dev/null) || return 1
    found=$(printf '%s\n' "$content" | __version_file_locate)
    if [ -z "$found" ]; then
        # A plain file says something, even if it's nothing: that's a mismatch
        [ "$(version_file_format)" = plain ] || return 1
        return 0
    fi
    printf '%s' "${found#*	}"
}

# The version in workflow.versionFile at <rev>, as this repository's tags
# spell it (v1.2.3); empty when there's no such file or it doesn't hold one
file_version() {
    local have
    have=$(version_file_raw "$1") || return 0
    have=$(normalize_version "$have")
    if is_stable_version "$have"; then
        printf '%s' "$have"
    fi
}

# check_version_file <rev> <version> <mode>
# If the project keeps its version in a file (workflow.versionFile, default
# VERSION), the file at <rev> must match the version being tagged. The release
# workflow checks the same thing, but only after the tag is already public.
# The file may write it with or without a "v", whatever the tag prefix is.
# Skipped when the file doesn't exist at <rev>, or has no version of its own.
check_version_file() {
    local rev="$1" version="$2" mode="$3" have
    have=$(version_file_raw "$rev") || return 0
    if [ "${have#v}" = "${version#"$TAG_PREFIX"}" ]; then
        return 0
    fi
    pre_flow_warn "$mode" "$VERSION_FILE says '$have', but this release is $version. Bump it on the branch before tagging."
}

# version_file_write <version>: set the version in the working tree's version
# file, keeping how it's written ("v" or not, quotes, spacing). Only a file
# git tracks: a .gitworkflow names the file, and a path git doesn't know is
# not one to write.
version_file_write() {
    local version="$1" path line have new tmp
    path="$WF_TOPLEVEL/$VERSION_FILE"
    if ! git -C "$WF_TOPLEVEL" ls-files --error-unmatch -- "$VERSION_FILE" >/dev/null 2>&1 || [ ! -f "$path" ]; then
        err "'$VERSION_FILE' isn't a file git tracks here; not writing it."
        return 1
    fi
    line=$(__version_file_locate <"$path")
    have="${line#*	}"
    line="${line%%	*}"
    new="${version#"$TAG_PREFIX"}"
    case "$have" in v*) new="v$new" ;; esac
    tmp="$path.git-workflow.$$"
    if [ "$(version_file_format)" = plain ]; then
        printf '%s\n' "$new" >"$tmp" || return 1
    elif [ -n "$line" ]; then
        awk -v n="$line" -v new="$new" -v fmt="$(version_file_format)" '
            NR == n {
                if (fmt == "json") {
                    if (match($0, /"version"[ \t]*:[ \t]*"[^"]*"/)) {
                        m = substr($0, RSTART, RLENGTH)
                        sub(/"[^"]*"$/, "\"" new "\"", m)
                        $0 = substr($0, 1, RSTART - 1) m substr($0, RSTART + RLENGTH)
                    }
                } else if (!sub(/"[^"]*"/, "\"" new "\"")) {
                    sub(/\047[^\047]*\047/, "\047" new "\047")
                }
            }
            { print }' "$path" >"$tmp" || {
            rm -f "$tmp"
            return 1
        }
    else
        err "'$VERSION_FILE' has no version of its own to set."
        return 1
    fi
    # cat, not mv: keep the file's mode and links
    cat "$tmp" >"$path" && rm -f "$tmp" || return 1
    line=$(__version_file_locate <"$path")
    if [ "${line#*	}" != "$new" ]; then
        err "couldn't find where $VERSION_FILE keeps its version to set it."
        return 1
    fi
}

# offer_version_commit <version>: on a new versioned branch, offer to set
# the version file to <version> and commit it
offer_version_commit() {
    local version="$1" have lock
    have=$(version_file_raw HEAD) || return 0
    [ "${have#v}" = "${version#"$TAG_PREFIX"}" ] && return 0
    yes_no "$VERSION_FILE says '${have:-nothing}'. Set it to $version and commit?" y || return 0
    version_file_write "$version" || return 1
    git -C "$WF_TOPLEVEL" commit -q -m "bump version to $version" -- "$VERSION_FILE" || return 1
    note "Committed $VERSION_FILE at $version."
    # The lock file records the version too; its own tool updates it
    case "$(version_file_format)" in
    json) lock=package-lock.json ;;
    cargo) lock=Cargo.lock ;;
    *) lock="" ;;
    esac
    case "$VERSION_FILE" in */*) lock="${VERSION_FILE%/*}/$lock" ;; esac
    if [ -n "${lock##*/}" ] && [ -f "$WF_TOPLEVEL/$lock" ]; then
        info "$lock records the version too: update it (npm install, cargo update -w) and commit before $(wf_cmd branch pre)."
    fi
}

# GitHub Actions URL of the repository the tags go to, if it's on GitHub
actions_url() {
    local slug
    slug=$(remote_slug "$UPSTREAM")
    case "$slug" in
    github.com/*) printf 'https://%s/actions' "$slug" ;;
    esac
}

# Push local commits so the tagged commit also lives on the remote branch.
ensure_branch_pushed() {
    local branch="$1" remote rref counts ahead behind
    remote=$(remote_for "$branch")
    rref=$(remote_ref "$branch")

    if ! remote_branch_exists "$branch"; then
        if yes_no "'$branch' is not on '$remote' yet. Push it now?" "y"; then
            git push -u "$remote" "$branch" || return 1
            return 0
        fi
        flow_warn "the prerelease will point at a commit that is on no remote branch." || return 1
        return 0
    fi

    counts=$(git rev-list --left-right --count "HEAD...$rref") || return 1
    ahead="${counts%%[[:space:]]*}"
    behind="${counts##*[[:space:]]}"

    if [ "$behind" -gt 0 ]; then
        err "'$branch' is $behind commit(s) behind '$rref'. Run '$(wf_cmd sync)' first."
        return 1
    fi
    if [ "$ahead" -gt 0 ]; then
        if yes_no "Push $ahead local commit(s) to '$rref' first?" "y"; then
            git push "$remote" "$branch" || return 1
        else
            flow_warn "the prerelease will include commits that are not on '$rref'." || return 1
        fi
    fi
}

# A tag cut on mainBranch must be on a commit that is on its remote copy:
# that's what gets released, and in pr mode main can't be pushed from here.
main_matches_remote() {
    local rref counts ahead behind
    rref=$(remote_ref "$MAIN_BRANCH")

    if ! remote_branch_exists "$MAIN_BRANCH"; then
        err "'$MAIN_BRANCH' is not on '$UPSTREAM' yet; there's nothing published to tag."
        return 1
    fi
    counts=$(git rev-list --left-right --count "HEAD...$rref") || return 1
    ahead="${counts%%[[:space:]]*}"
    behind="${counts##*[[:space:]]}"

    if [ "$behind" -gt 0 ]; then
        err "'$MAIN_BRANCH' is $behind commit(s) behind '$rref'. Run '$(wf_cmd sync)' first."
        return 1
    fi
    if [ "$ahead" -gt 0 ]; then
        err "'$MAIN_BRANCH' has $ahead local commit(s) that aren't on '$rref'; a tag on them would release code '$rref' doesn't have."
        if pr_only_branch "$MAIN_BRANCH"; then
            info "Get them onto '$MAIN_BRANCH' through a pull request first ('git switch -c <name>' moves them to a branch)."
        else
            info "Push them first: $(wf_cmd push)"
        fi
        return 1
    fi
}

# tag_and_push <tag> <rev> <message>: an annotated tag, pushed on its own to
# UPSTREAM. The local tag is removed again if the push fails.
tag_and_push() {
    git tag -a "$1" -m "$3" "$2" || return 1
    if ! git push "$UPSTREAM" "refs/tags/$1"; then
        git tag -d "$1" >/dev/null
        err "push failed; removed local tag '$1'."
        return 1
    fi
}

prerelease_usage() {
    local b
    b=$(wf_cmd branch)
    cat <<EOF
usage: $b prerelease [label | $VFMT | full-tag] [-n|--dry-run] [-l|--list] [-y|--yes]

Tag HEAD of the current $(versioned_prefixes) branch as a prerelease and push the
tag, which triggers the release workflow (published as a GitHub prerelease).
Flows that release from main (workflow.releaseFromMain) also tag $MAIN_BRANCH, with
the version from $VFMT or the $VERSION_FILE file; then '$b release' promotes it.

  $b pre              -> $VEX-$PRERELEASE_LABEL.N  (N = next free number)
  $b pre beta         -> $VEX-beta.N
  $b pre $VEX       -> $VEX-$PRERELEASE_LABEL.N, for that version
  $b pre $VEX-rc.7  -> exactly that tag
  $b pre -n           -> show the tag that would be created, change nothing
  $b pre -l           -> list prerelease tags for this branch's version
  $b pre -y           -> answer the questions with yes (flow warnings still ask)
EOF
}

pre_flow_warn() {
    if [ "$1" = "dry" ]; then
        warn "$2"
        return 0
    fi
    flow_warn "$2"
}

prerelease_branch() {
    # shellcheck disable=SC2154
    local mode="create" arg="" branch="$working_branch"
    local base tag label latest sha existing url on_main=""

    while [ "$#" -gt 0 ]; do
        case "$1" in
        -n | --dry-run) mode="dry" ;;
        -l | --list) mode="list" ;;
        -y | --yes) ASSUME_YES=1 ;;
        -h | --help)
            prerelease_usage
            return 0
            ;;
        -*)
            err "unknown option: $1"
            prerelease_usage >&2
            return 1
            ;;
        *)
            if [ -n "$arg" ]; then
                err "too many arguments."
                prerelease_usage >&2
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
    arg=$(normalize_version "$arg")
    # Flows with workflow.releaseFromMain release straight from main
    if [ "$RELEASE_FROM_MAIN" = true ] && [ "$branch" = "$MAIN_BRANCH" ]; then
        on_main=1
        # Tag what main is now (fast-forward only, so local work is never lost)
        if [ "$mode" = "create" ]; then
            pull_branch "$MAIN_BRANCH" || return 1
        fi
    fi

    # A plain X.Y.Z names the version; the label stays the default
    if is_stable_version "$arg"; then
        if [ -n "$base" ] && [ "$arg" != "$base" ] && [ "$mode" != "list" ]; then
            pre_flow_warn "$mode" "'$arg' does not match this branch's version '$base'." || return 1
        fi
        base="$arg"
        arg=""
    fi
    if [ -n "$on_main" ] && [ -z "$base" ] && ! is_prerelease_version "$arg"; then
        base=$(file_version HEAD)
        if [ -z "$base" ]; then
            err "no version to prerelease: '$MAIN_BRANCH' has no $VFMT in $VERSION_FILE file. Name it: $(wf_cmd branch pre "$VEX")"
            return 1
        fi
    fi

    if [ "$mode" = "list" ]; then
        if [ -z "$base" ] || ! is_stable_version "$base"; then
            err "cannot list prereleases: no $VFMT version in branch name '$branch'"
            return 1
        fi
        sync_remote
        prerelease_tags_for "$base"
        return 0
    fi

    if [ -n "$on_main" ]; then
        :
    elif [ -z "$base" ]; then
        pre_flow_warn "$mode" "prereleases are cut from $(versioned_prefixes) branches; '$branch' isn't one." || return 1
    elif ! is_stable_version "$base"; then
        pre_flow_warn "$mode" "branch version '$base' is not $VFMT; cannot derive a prerelease tag from it." || return 1
        base=""
    fi

    sync_remote

    # Work out the tag
    if is_prerelease_version "$arg"; then
        tag="$arg"
        if [ -n "$base" ] && [ "$(version_base "$tag")" != "$base" ]; then
            pre_flow_warn "$mode" "'$tag' does not match this branch's version '$base'." || return 1
        fi
        base=$(version_base "$tag")
    else
        label="${arg:-$PRERELEASE_LABEL}"
        if ! [[ "$label" =~ ^[0-9A-Za-z-]+$ ]]; then
            err "invalid prerelease label '$label' (letters, digits and '-' only), or pass a full tag like $VEX-rc.1."
            return 1
        fi
        if [ -z "$base" ]; then
            err "no version in branch name; pass a full tag instead, e.g. '$(wf_cmd branch pre "$VEX-rc.1")'."
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
        pre_flow_warn "$mode" "'$base' is not newer than the latest release '$latest'." || return 1
    fi

    check_version_file HEAD "$base" "$mode" || return 1

    sha=$(git rev-parse --short HEAD)

    if [ "$mode" = "dry" ]; then
        info "Would tag $sha ($(git log -1 --format=%s HEAD)) as '$tag' and push it to '$UPSTREAM'."
        existing=$(prerelease_tags_for "$base" | tr '\n' ' ')
        [ -n "$existing" ] && info "Existing prereleases for $base: $existing"
        return 0
    fi

    if ! git diff --quiet HEAD -- 2>/dev/null; then
        flow_warn "you have uncommitted changes; they will NOT be in '$tag'." || return 1
    fi

    if [ -n "$on_main" ]; then
        main_matches_remote || return 1
    else
        ensure_branch_pushed "$branch" || return 1
    fi

    if ! yes_no "Create prerelease tag '$tag' at $sha and push it (triggers the release workflow)?"; then
        info "Aborted."
        return 1
    fi

    tag_and_push "$tag" HEAD "prerelease: $tag" || return 1

    note "Pushed prerelease '$tag'."
    url=$(actions_url)
    [ -n "$url" ] && note "Watch the release run: $url  (or: gh run watch)"
    if [ -n "$on_main" ]; then
        info "Once it's tested: $(wf_cmd branch release "$base")"
    fi
    return 0
}

release_usage() {
    local b
    b=$(wf_cmd branch)
    cat <<EOF
usage: $b release [$VFMT] [-n|--dry-run] [-y|--yes]

Flows that release from main (workflow.releaseFromMain): tag the commit a
prerelease tested as $VFMT and push only the tag. $MAIN_BRANCH isn't pushed, so
it works when it only takes pull requests. The commit must be on $MAIN_BRANCH.

  $b release          -> $VEX from the newest unreleased prerelease ($VEX-rc.2)
  $b release $VEX   -> $VEX from its newest prerelease
  $b release -n       -> show what would be tagged, change nothing
  $b release -y       -> answer the questions with yes (flow warnings still ask)
EOF
}

# The newest version that has a prerelease but no release yet
newest_unreleased_version() {
    local t base latest
    latest=$(latest_stable_tag)
    for t in $(git tag --list "$TAG_PREFIX*-*" --sort=-v:refname); do
        is_prerelease_version "$t" || continue
        base=$(version_base "$t")
        tag_exists "$base" && continue
        if [ -n "$latest" ] && ! version_gt "$base" "$latest"; then
            continue
        fi
        printf '%s' "$base"
        return 0
    done
}

# git workflow branch release [version] [-n] [-y]: promote a tested prerelease
release_main() {
    local mode="create" version="" latest pre target main_ref sha since what url

    while [ "$#" -gt 0 ]; do
        case "$1" in
        -n | --dry-run) mode="dry" ;;
        -y | --yes) ASSUME_YES=1 ;;
        -h | --help)
            release_usage
            return 0
            ;;
        -*)
            err "unknown option: $1"
            release_usage >&2
            return 1
            ;;
        *)
            if [ -n "$version" ]; then
                err "too many arguments."
                release_usage >&2
                return 1
            fi
            version="$1"
            ;;
        esac
        shift
    done

    if [ "$RELEASE_FROM_MAIN" != true ]; then
        err "the $WF_FLOW flow doesn't release from $MAIN_BRANCH (workflow.releaseFromMain); releases go through $(versioned_prefixes) branches, with $(wf_cmd branch finish)."
        return 1
    fi

    sync_remote
    main_ref=$(remote_ref "$MAIN_BRANCH")
    if ! remote_branch_exists "$MAIN_BRANCH"; then
        err "'$MAIN_BRANCH' is not on '$UPSTREAM' yet; there's nothing published to release."
        return 1
    fi

    if [ -z "$version" ]; then
        version=$(newest_unreleased_version)
        if [ -z "$version" ]; then
            err "there's no prerelease to promote. Cut one on '$MAIN_BRANCH' first ($(wf_cmd branch pre)), or name the version: $(wf_cmd branch release "$VEX")"
            return 1
        fi
    else
        version=$(normalize_version "$version")
        if ! is_stable_version "$version"; then
            err "'$version' is not a $VFMT version."
            return 1
        fi
    fi
    if tag_exists "$version"; then
        err "'$version' has already been released."
        return 1
    fi
    latest=$(latest_stable_tag)
    if [ -n "$latest" ] && ! version_gt "$version" "$latest"; then
        pre_flow_warn "$mode" "'$version' is not newer than the latest release '$latest'." || return 1
    fi

    # The newest prerelease is what was tested last
    pre=$(prerelease_tags_for "$version" | tail -n 1)
    if [ -n "$pre" ]; then
        target=$(git rev-parse "$pre^{commit}") || return 1
        what="$pre"
        if ! git merge-base --is-ancestor "$target" "$main_ref"; then
            err "$pre is not on '$main_ref', and a release has to be a commit $MAIN_BRANCH has."
            info "If it was cut on a $(versioned_prefixes) branch, finish that branch instead."
            return 1
        fi
    else
        target=$(git rev-parse "$main_ref") || return 1
        what="$main_ref"
        pre_flow_warn "$mode" "no prereleases were cut for $version, so this releases '$main_ref' untested." || return 1
    fi
    check_version_file "$target" "$version" "$mode" || return 1

    sha=$(git rev-parse --short "$target")
    since=$(git rev-list --count "$target..$main_ref")

    if [ "$mode" = "dry" ]; then
        info "Would tag $sha ($what) as '$version' and push it to '$UPSTREAM'."
        [ "$since" -gt 0 ] && info "'$main_ref' has $since commit(s) after $what; they wouldn't be in $version."
        return 0
    fi

    if [ "$since" -gt 0 ]; then
        note "'$main_ref' has $since commit(s) after $what; they aren't in $version (they go in the next release)."
    fi
    if ! yes_no "Tag $sha ($what) as '$version' and push it (triggers the release workflow)?"; then
        info "Aborted."
        return 1
    fi

    tag_and_push "$version" "$target" "release: $version" || return 1

    note "Released '$version'."
    url=$(actions_url)
    [ -n "$url" ] && note "Watch the release run: $url  (or: gh run watch)"
    return 0
}
