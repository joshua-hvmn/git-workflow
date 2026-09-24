#!/bin/bash

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.

# Include guard to prevent redundant parsing
if [ -n "${__BRANCH_UTILS_LOADED:-}" ]; then
    return 0
fi
__BRANCH_UTILS_LOADED=1

if [ -z "$__CORE_UTILS_LOADED" ]; then
    . "$GIT_SCRIPTS_HOME_DIR/lib/git-core-utils.sh"
fi
if [ -z "${__RELEASE_UTILS_LOADED:-}" ]; then
    . "$GIT_SCRIPTS_HOME_DIR/lib/git-release-utils.sh"
fi

# FUNCTIONS

check_clean_tree() {
    if [ -n "$(git ls-files --others --exclude-standard)" ]; then
        err "working tree has files that autostash can't stash. Commit, stash -u, or ignore them first."
        return 1
    fi
}

check_for_branch() {
    local target_branch="${1:-$DEV_BRANCH}"
    if ! git rev-parse --verify --quiet "refs/heads/$target_branch" >/dev/null; then
        err "could not find local branch '$target_branch'."
        return 1
    fi
}

# Other release branches, local or remote (gitflow allows one at a time)
other_release_branches() {
    {
        git for-each-ref --format='%(refname:short)' "refs/heads/${RELEASE_PREFIX}"
        git for-each-ref --format='%(refname:lstrip=3)' "refs/remotes/$REMOTE/${RELEASE_PREFIX}"
    } | sort -u | grep -vxF "${1:-}" || true
}

start_branch() {
    local start_mode="${1:-}"
    local new_branch_name="${2:-"null"}"
    local new_branch_type="topic"
    local base_branch="$DEV_BRANCH"
    local prefix=""
    local full_branch_name others
    local start_message="Enter new topic branch name:"

    if [ -z "$start_mode" ]; then
        err "usage: git b start <topic|hotfix|release> [branch-name]"
        return 1
    fi

    case "$start_mode" in
    topic | t | -t | --topic)
        :
        ;;
    hotfix | h | -h | --hotfix)
        new_branch_type="hotfix"
        base_branch="$MAIN_BRANCH"
        prefix="$HOTFIX_PREFIX"
        start_message="Enter new hotfix name (e.g., v1.2.3):"
        ;;
    release | r | -r | --release)
        new_branch_type="release"
        prefix="$RELEASE_PREFIX"
        start_message="Enter new release name (e.g., v1.2.3):"
        ;;
    *)
        err "unknown mode: $start_mode"
        return 1
        ;;
    esac

    check_clean_tree || return 1
    sync_remote
    check_for_branch "$base_branch" || return 1

    get_user_input "$new_branch_name" "$start_message" || return 1
    new_branch_name="$REPLY"
    full_branch_name="$prefix$new_branch_name"

    if [ "$new_branch_type" != "topic" ]; then
        validate_new_version "$new_branch_name" || return 1
    fi

    if [ "$new_branch_type" = "release" ]; then
        others=$(other_release_branches "$full_branch_name")
        if [ -n "$others" ]; then
            flow_warn "git flow allows one release branch at a time; already open: $(printf '%s' "$others" | tr '\n' ' ')" || return 1
        fi
    fi

    if git rev-parse --verify --quiet "refs/heads/$full_branch_name" >/dev/null; then
        err "branch '$full_branch_name' already exists."
        return 1
    fi

    info "Starting $new_branch_type branch '$full_branch_name' from '$base_branch'..."
    rb_pull_function "$base_branch" || return 1
    git switch -c "$full_branch_name" "$base_branch" || return 1
    git push -u "$REMOTE" "$full_branch_name"
}

finish_branch() {
    local finish_choice="${1:-$working_branch}"
    local finish_type=""
    local finish_version=""
    local push_refs

    if [ -z "$finish_choice" ]; then
        err "not on a branch; pass the branch to finish."
        return 1
    fi

    detect_protected_branch "fin_branch" "$finish_choice" || return 1
    check_clean_tree || return 1
    check_for_branch "$finish_choice" || return 1
    sync_remote
    check_for_branch "$MAIN_BRANCH" || return 1
    check_for_branch "$DEV_BRANCH" || return 1

    case "$finish_choice" in
    "$RELEASE_PREFIX"*) finish_type="release" ;;
    "$HOTFIX_PREFIX"*) finish_type="hotfix" ;;
    esac

    rb_pull_function "$finish_choice" || return 1

    if [ -n "$finish_type" ]; then
        finish_version=$(branch_version "$finish_choice")
        validate_new_version "$finish_version" || return 1

        if [ -z "$(prerelease_tags_for "$finish_version")" ]; then
            note "No prereleases were cut for $finish_version (git b pre). Releasing untested artifacts."
        else
            note "Prereleases for $finish_version: $(prerelease_tags_for "$finish_version" | tr '\n' ' ')"
        fi

        # Check for release branches and warn if on a hotfix and on Git Flow
        if [ "$finish_type" = "hotfix" ] && [ "$TRUNK_MODE" -eq 0 ]; then
            local open_releases
            open_releases=$(other_release_branches "")
            if [ -n "$open_releases" ]; then
                warn "release branch(es) open: $(printf '%s' "$open_releases" | tr '\n' ' ')- git flow also merges hotfixes into them; do that manually after this."
            fi
        fi

        if [ "$TRUNK_MODE" -eq 1 ]; then
            yes_no "Merge '$finish_choice' into $MAIN_BRANCH, tag $finish_version, and push?" || return 1
        else
            yes_no "Merge '$finish_choice' into $MAIN_BRANCH and $DEV_BRANCH, tag $finish_version, and push?" || return 1
        fi

        rb_pull_function "$MAIN_BRANCH" || return 1
        git merge --no-ff --no-edit -m "Merge $finish_type $finish_version" "$finish_choice" || return 1
        git tag -a "$finish_version" -m "$finish_type: $finish_version" || return 1
        push_refs="$MAIN_BRANCH"

        # If Git Flow, back merge from main to dev
        if [ "$TRUNK_MODE" -eq 0 ]; then
            rb_pull_function "$DEV_BRANCH" || return 1
            if ! git merge --ff-only "$MAIN_BRANCH" 2>/dev/null; then
                git merge --no-edit "$MAIN_BRANCH" || {
                    err "back-merge of $MAIN_BRANCH into $DEV_BRANCH failed. Resolve, commit, then run:"
                    info " git push --atomic $REMOTE $MAIN_BRANCH $DEV_BRANCH refs/tags/$finish_version"
                    return 1
                }
            fi
            push_refs="$MAIN_BRANCH $DEV_BRANCH"
        fi

        # push_refs must be unquoted
        # shellcheck disable=SC2086
        git push --atomic "$REMOTE" $push_refs "refs/tags/$finish_version" || return 1
    else
        yes_no "Merge '$finish_choice' into $DEV_BRANCH and push?" || return 1
        rb_pull_function "$DEV_BRANCH" || return 1
        git merge --no-ff --no-edit "$finish_choice" || return 1
        git push "$REMOTE" "$DEV_BRANCH" || return 1
    fi

    delete_branch "$finish_choice" || note "Kept branch '$finish_choice'."
}

delete_branch() {
    local delete_choice="${1:-$working_branch}"
    local force_mode="${2:-}"
    local return_to=""

    detect_protected_branch "del_branch" "$delete_choice" || return 1
    check_clean_tree || return 1

    if [ "$(get_working_branch)" = "$delete_choice" ]; then
        git switch "$DEV_BRANCH" || {
            err "failed to switch to $DEV_BRANCH (does it exist?)"
            return 1
        }
        return_to="$delete_choice"
    fi

    case "$force_mode" in
    yes | -y | --yes | --y | y | d | -d | --d | --delete)
        info "Deleting."
        ;;
    *)
        if ! yes_no "Delete '$delete_choice' locally and remotely?"; then
            info "Deletion aborted."
            [ -n "$return_to" ] && git switch "$return_to"
            return 1
        fi
        ;;
    esac

    local del_flag="-d"
    git merge-base --is-ancestor "$delete_choice" HEAD 2>/dev/null && del_flag="-D"
    git branch "$del_flag" "$delete_choice" || {
        [ -n "$return_to" ] && git switch "$return_to"
        return 1
    }
    if remote_branch_exists "$delete_choice"; then
        git push "$REMOTE" --delete "$delete_choice" || warn "remote delete failed"
    fi
    info "Branch $delete_choice deleted."
}

show_config() {
    local flow="git flow"
    [ "$TRUNK_MODE" -eq 1 ] && flow="trunk / GitHub flow (devBranch = mainBranch)"
    cat >&2 <<EOF
git-workflow settings (git config workflow.<key>):
  flow             $flow
  mainBranch       $MAIN_BRANCH
  devBranch        $DEV_BRANCH
  remote           $REMOTE
  releasePrefix    $RELEASE_PREFIX
  hotfixPrefix     $HOTFIX_PREFIX
  prereleaseLabel  $PRERELEASE_LABEL
  strict           $STRICT
  protected        $MAIN_BRANCH $DEV_BRANCH ${EXTRA_PROTECTED}
EOF
}
