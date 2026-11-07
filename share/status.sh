# shellcheck shell=bash
# Sourced by the git-workflow commands; not executable on its own.

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.
#
# `git workflow branch status`: where you are in the flow and what comes
# next, the open branches of each type, and what's been left half done (a
# merged release that was never tagged, a prerelease never released).

# Include guard to prevent redundant parsing
if [ -n "${__WF_STATUS_LOADED:-}" ]; then
    return 0
fi
__WF_STATUS_LOADED=1

if [ -z "${__WF_FLOW_LOADED:-}" ]; then
    . "$GIT_WORKFLOW_DATADIR/flow.sh"
fi

# "1 commit", "3 commits"
__commits() {
    if [ "$1" -eq 1 ]; then
        printf '1 commit'
    else
        printf '%s commits' "$1"
    fi
}

# merged_into <branch> <ref>: how <branch> got into <ref>: "commit" (its
# commits are there), "changes" (squashed or rebased), or nothing. A branch
# with no commits of its own isn't merged, it's new.
merged_into() {
    local branch="$1" ref="$2"
    git rev-parse --verify --quiet "$ref" >/dev/null || return 0
    if git merge-base --is-ancestor "$branch" "$ref"; then
        if [ "$(merge_point "$branch" "$ref")" != "$(git rev-parse "$branch")" ]; then
            printf commit
        fi
    elif content_merged "$branch" "$ref"; then
        printf changes
    fi
}

# Open branches of the type without a prefix: local ones only (a remote's
# unprefixed branches are anyone's)
__unprefixed_branches() {
    local type="$1" b
    git for-each-ref --format='%(refname:short)' refs/heads | while IFS= read -r b; do
        is_protected_branch "$b" && continue
        [ "$(branch_type "$b")" = "$type" ] && printf '%s\n' "$b"
    done
}

# What finish does with a branch of <type>, in words
__finish_does() {
    local type="$1" version="$2" into
    type_get "$type"
    into=$(resolve_point "$T_INTO")
    if [ "$T_INTEGRATE" = pr ]; then
        printf 'opens a pull request into %s' "$into"
        return 0
    fi
    printf 'merges it into %s' "$into"
    [ -n "$version" ] && printf ', tags %s' "$version"
    if [ "$T_BACK" = dev ] && [ "$DEV_BRANCH" != "$into" ]; then
        printf ', merges %s back into %s' "$into" "$DEV_BRANCH"
    fi
    printf ' and pushes'
}

# The current branch: what it is, how far along, and the next step
__status_current() {
    local branch="$working_branch" type into into_ref version how pres="" last after=0
    local own unpushed state="" url="" finish pre_cmd

    if [ -z "$branch" ]; then
        printf 'Not on a branch (detached HEAD).\n'
        return 0
    fi
    finish=$(wf_cmd branch finish)
    pre_cmd=$(wf_cmd branch pre)

    if is_protected_branch "$branch"; then
        if [ "$branch" = "$MAIN_BRANCH" ]; then
            printf 'On %s, the main branch.\n' "$branch"
        elif [ "$branch" = "$DEV_BRANCH" ]; then
            printf 'On %s, the dev branch.\n' "$branch"
        else
            printf 'On %s, a protected branch.\n' "$branch"
        fi
        if [ "$RELEASE_FROM_MAIN" = true ] && [ "$branch" = "$MAIN_BRANCH" ]; then
            version=$(newest_unreleased_version)
            if [ -n "$version" ]; then
                printf '  Next: %s promotes %s.\n' "$(wf_cmd branch release)" \
                    "$(prerelease_tags_for "$version" | tail -n 1)"
            else
                printf '  Next: %s <type>, or %s to test a release of %s.\n' \
                    "$(wf_cmd branch start)" "$pre_cmd" "$MAIN_BRANCH"
            fi
        else
            printf '  Next: %s <type> (%s).\n' "$(wf_cmd branch start)" "$(types_list)"
        fi
        return 0
    fi

    type=$(branch_type "$branch")
    if [ -z "$type" ]; then
        printf "On %s, which isn't a branch of the %s flow (%s).\n" "$branch" "$WF_FLOW" "$(types_list)"
        return 0
    fi
    type_get "$type"
    into=$(resolve_point "$T_INTO")
    into_ref=$(remote_ref "$into")
    remote_branch_exists "$into" || into_ref="$into"
    version=$(branch_version "$branch")

    if [ -n "$version" ]; then
        printf 'On %s, the %s branch for %s, into %s.\n' "$branch" "$type" "$version" "$into"
    else
        printf 'On %s, a %s branch into %s.\n' "$branch" "$type" "$into"
    fi

    own=$(git rev-list --count "$into_ref..$branch" 2>/dev/null) || own=0
    if [ "$own" -eq 0 ]; then
        own="No commits of its own yet"
    else
        own="$(__commits "$own") of its own"
    fi
    if ! remote_branch_exists "$branch"; then
        unpushed="not on '$(remote_for "$branch")' yet"
    else
        unpushed=$(git rev-list --count "$(remote_ref "$branch")..$branch")
        if [ "$unpushed" -eq 0 ]; then
            unpushed="all pushed"
        else
            unpushed="$unpushed not pushed"
        fi
    fi
    printf '  %s; %s.\n' "$own" "$unpushed"

    if [ -n "$version" ]; then
        pres=$(prerelease_tags_for "$version" | paste -sd ' ' -)
        if [ -z "$pres" ]; then
            printf '  No prereleases yet.\n'
        else
            last=$(prerelease_tags_for "$version" | tail -n 1)
            after=$(git rev-list --count "$last..$branch")
            if [ "$after" -gt 0 ]; then
                printf '  Prereleases: %s (%s after %s).\n' "$pres" "$(__commits "$after")" "$last"
            else
                printf '  Prereleases: %s (the tip is %s).\n' "$pres" "$last"
            fi
        fi
    fi

    how=$(merged_into "$branch" "$into_ref")
    if [ -z "$how" ] && [ "$T_INTEGRATE" = pr ] && forge_source 2>/dev/null && forge_require 2>/dev/null; then
        state=$(forge_pr_find "$branch" "$(remote_for "$branch")" 2>/dev/null) || state=""
        url="${state#* }"
        case "$state" in
        MERGED\ *) how=changes ;;
        OPEN\ *)
            printf '  Pull request: %s\n' "$url"
            if [ -n "$version" ]; then
                printf '  Next: once it is merged, %s tags %s.\n' "$finish" "$version"
            else
                printf '  Next: once it is merged, %s deletes the branch.\n' "$finish"
            fi
            return 0
            ;;
        esac
    fi

    if [ -n "$how" ]; then
        printf '  Merged into %s%s.\n' "$into_ref" "${url:+ ($url)}"
        if [ -n "$version" ] && ! tag_exists "$version"; then
            printf '  Next: %s tags %s and deletes the branch.\n' "$finish" "$version"
        else
            printf '  Next: %s deletes the branch.\n' "$finish"
        fi
        return 0
    fi

    if [ -n "$version" ] && [ -z "$pres" ]; then
        printf '  Next: %s to test it, then %s (%s).\n' "$pre_cmd" "$finish" "$(__finish_does "$type" "$version")"
    elif [ -n "$version" ] && [ "$after" -gt 0 ]; then
        printf '  Next: %s to test what changed, or %s (%s).\n' "$pre_cmd" "$finish" "$(__finish_does "$type" "$version")"
    else
        printf '  Next: %s (%s).\n' "$finish" "$(__finish_does "$type" "$version")"
    fi
}

# The open branches of each type
__status_open() {
    local t list any=""
    printf '\nOpen branches:\n'
    for t in $WF_TYPES; do
        type_get "$t"
        if [ -n "$T_PREFIX" ]; then
            list=$(branches_of_type "$t" | paste -sd ' ' -)
        else
            list=$(__unprefixed_branches "$t" | paste -sd ' ' -)
        fi
        [ -n "$list" ] || continue
        any=1
        printf '  %-9s %s\n' "$t" "$list"
    done
    [ -n "$any" ] || printf '  none\n'
}

# What's been left half done
__status_attention() {
    local out="" t b version into_ref ref version_tag
    for t in $WF_TYPES; do
        type_get "$t"
        into_ref=$(remote_ref "$(resolve_point "$T_INTO")")
        if type_versioned "$t"; then
            # A versioned branch merged (with a merge commit) but never tagged:
            # finish wasn't run again after its pull request merged
            for b in $(branches_of_type "$t"); do
                ref="refs/heads/$b"
                git rev-parse --verify --quiet "$ref" >/dev/null || ref="refs/remotes/$(remote_ref "$b")"
                version_tag="${b#"$T_PREFIX"}"
                tag_exists "$version_tag" && continue
                [ "$(merged_into "$ref" "$into_ref")" = commit ] || continue
                out="$out  $b is merged into $into_ref, but $version_tag isn't tagged: $(wf_cmd branch finish "$b")$__NL"
            done
        elif [ -z "$T_PREFIX" ]; then
            # Merged local branches that are still around
            for b in $(__unprefixed_branches "$t"); do
                [ "$b" = "$working_branch" ] && continue
                [ -n "$(merged_into "$b" "$into_ref")" ] || continue
                out="$out  $b is merged into $into_ref: $(wf_cmd branch delete "$b")$__NL"
            done
        fi
    done
    if [ "$RELEASE_FROM_MAIN" = true ]; then
        version=$(newest_unreleased_version)
        if [ -n "$version" ] && [ "$working_branch" != "$MAIN_BRANCH" ]; then
            out="$out  $version has prereleases but no release: $(wf_cmd branch release "$version")$__NL"
        fi
    fi
    if [ -n "$out" ]; then
        printf '\nLeft to do:\n%s' "$out"
    fi
}

# show_status [--no-fetch]
show_status() {
    local fetch=1 latest
    while [ "$#" -gt 0 ]; do
        case "$1" in
        --no-fetch) fetch="" ;;
        *)
            err "unknown argument: $1. usage: $(wf_cmd branch status "[--no-fetch]")"
            return 1
            ;;
        esac
        shift
    done
    [ -z "$fetch" ] || sync_remote

    latest=$(latest_stable_tag)
    if [ "$DEV_BRANCH" != "$MAIN_BRANCH" ]; then
        printf '%s flow: %s and %s; ' "$WF_FLOW" "$MAIN_BRANCH" "$DEV_BRANCH"
    else
        printf '%s flow: %s; ' "$WF_FLOW" "$MAIN_BRANCH"
    fi
    if [ -n "$latest" ]; then
        printf 'latest release %s.\n\n' "$latest"
    else
        printf 'no releases yet.\n\n'
    fi

    __status_current
    __status_open
    __status_attention
}
