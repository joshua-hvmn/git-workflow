# shellcheck shell=bash
# Sourced by the git-* commands; not executable on its own.

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

if [ -z "${__CORE_UTILS_LOADED:-}" ]; then
    . "$GIT_WORKFLOW_LIBDIR/git-core-utils.sh"
fi
if [ -z "${__RELEASE_UTILS_LOADED:-}" ]; then
    . "$GIT_WORKFLOW_LIBDIR/git-release-utils.sh"
fi

# FUNCTIONS

require_clean_tree() {
    if ! git diff --quiet HEAD -- 2>/dev/null; then
        err "you have uncommitted changes. Commit or stash them first."
        git status --short >&2
        return 1
    fi
}

check_for_branch() {
    local target_branch="${1:-$DEV_BRANCH}"
    git rev-parse --verify --quiet "refs/heads/$target_branch" >/dev/null && return 0

    if remote_branch_exists "$target_branch"; then
        git branch --quiet --track "$target_branch" "$REMOTE/$target_branch" || return 1
        note "Created local '$target_branch' tracking '$REMOTE/$target_branch'."
        return 0
    fi

    err "could not find local branch '$target_branch' locally or on '$REMOTE'."
    return 1
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
    local new_branch_name="${2:-}"
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

    if remote_branch_exists "$full_branch_name"; then
        err "branch '$full_branch_name' already exists on '$REMOTE'. Pick another name, or check it out: git switch $full_branch_name"
        return 1
    fi

    info "Starting $new_branch_type branch '$full_branch_name' from '$base_branch'..."
    rb_pull_function "$base_branch" || return 1
    git switch -c "$full_branch_name" "$base_branch" || return 1
    git push -u "$REMOTE" "$full_branch_name"
}

# finish_rollback <branch> [tag] [main_before] [dev_before]
# Abort a half done merge, delete created tag, reset main and dev to where they were and go back
# to <branch>. Only local refs are touched
finish_rollback() {
    local branch="$1" tag="${2:-}" main_before="${3:-}" dev_before="${4:-}"

    if git rev-parse --verify --quiet MERGE_HEAD >/dev/null; then
        git merge --abort || return 1
    fi
    git switch --quiet "$branch" || return 1
    if [ -n "$tag" ]; then
        git tag -d "$tag" >/dev/null || return 1
    fi
    if [ -n "$main_before" ]; then
        git branch -f "$MAIN_BRANCH" "$main_before" || return 1
    fi
    if [ -n "$dev_before" ]; then
        git branch -f "$DEV_BRANCH" "$dev_before" || return 1
    fi
}

finish_push_failed() {
    local branch="$1" version="$2" refs="$3" main_before="$4" dev_before="${5:-}"

    err "push to '$REMOTE' was rejected; nothing was published."
    info "Locally, $refs and tag $version are ahead of '$REMOTE'. To retry the push:"
    info "  git push --atomic $REMOTE $refs refs/tags/$version && git b delete $branch"

    if yes_no "Roll back the local merge and tag instead (then fix the cause and run 'git b finish' again)?"; then
        finish_rollback "$branch" "$version" "$main_before" "$dev_before" || return 1
        info "Rolled back. You are on '$branch' again."
    fi
}

# Topic branches with workflow.finishTopic=pr: publish and open a pull request
# instead of merging locally (for repos where devBranch requires reviews).
finish_topic_pr() {
    local branch="$1" url

    if ! command -v gh >/dev/null 2>&1; then
        err "workflow.finishTopic is 'pr', but the GitHub CLI (gh) isn't installed."
        return 1
    fi
    git push -u "$REMOTE" "$branch" || return 1
    if url=$(gh pr view "$branch" --json url --jq .url 2>/dev/null) && [ -n "$url" ]; then
        note "A pull request for '$branch' is already open: $url"
        return 0
    fi
    yes_no "Open a pull request from '$branch' into '$DEV_BRANCH'?" "y" || return 1
    gh pr create --base "$DEV_BRANCH" --head "$branch" --fill
}

finish_topic() {
    local branch="$1" dev_before

    if [ "$FINISH_TOPIC" = pr ]; then
        finish_topic_pr "$branch"
        return
    fi

    yes_no "Merge '$branch' into $DEV_BRANCH and push?" || return 1

    if ! rb_pull_function "$DEV_BRANCH"; then
        git switch --quiet "$branch" 2>/dev/null || :
        return 1
    fi
    dev_before=$(git rev-parse "$DEV_BRANCH")

    if ! git merge --no-ff --no-edit "$branch"; then
        err "merging '$branch' into '$DEV_BRANCH' conflicted."
        finish_rollback "$branch" "" "" "$dev_before" || return 1
        info "Rolled back; you are on '$branch'. Bring in the latest '$DEV_BRANCH'"
        info "(git merge $REMOTE/$DEV_BRANCH), resolve the conflicts there, then run 'git b finish' again."
        return 1
    fi

    if ! git push "$REMOTE" "$DEV_BRANCH"; then
        err "push to '$REMOTE' was rejected; nothing was published."
        finish_rollback "$branch" "" "" "$dev_before" || return 1
        info "Rolled back; you are on '$branch'. If someone pushed to '$DEV_BRANCH' first, run 'git b finish' again."
        info "If '$DEV_BRANCH' only accepts pull requests: git config workflow.finishTopic pr"
        return 1
    fi

    delete_branch "$branch" || note "Kept branch '$branch'."
}

finish_release() {
    local branch="$1" type="$2"
    local version push_refs open_releases main_before="" dev_before=""

    version=$(branch_version "$branch")
    validate_new_version "$version" || return 1
    check_version_file "$branch" "$version" finish || return 1

    if [ -z "$(prerelease_tags_for "$version")" ]; then
        note "No prereleases were cut for $version (git b pre). Releasing untested artifacts."
    else
        note "Prereleases for $version: $(prerelease_tags_for "$version" | tr '\n' ' ')"
    fi

    if [ "$type" = "hotfix" ] && [ "$TRUNK_MODE" -eq 0 ]; then
        open_releases=$(other_release_branches "")
        if [ -n "$open_releases" ]; then
            warn "release branch(es) open: $(printf '%s' "$open_releases" | tr '\n' ' ')- git flow also merges hotfixes into them; do that manually after this."
        fi
    fi

    if [ "$TRUNK_MODE" -eq 1 ]; then
        yes_no "Merge '$branch' into $MAIN_BRANCH, tag $version, and push?" || return 1
    else
        yes_no "Merge '$branch' into $MAIN_BRANCH and $DEV_BRANCH, tag $version, and push?" || return 1
    fi

    if ! rb_pull_function "$MAIN_BRANCH"; then
        git switch --quiet "$branch" 2>/dev/null || :
        return 1
    fi
    main_before=$(git rev-parse "$MAIN_BRANCH")
    if ! git merge --no-ff --no-edit -m "Merge $type $version" "$branch"; then
        err "merging '$branch' into '$MAIN_BRANCH' conflicted."
        finish_rollback "$branch" "" "$main_before" || return 1
        info "Rolled back; you are on '$branch'. Bring in the latest '$MAIN_BRANCH'"
        info "(git merge $REMOTE/$MAIN_BRANCH), resolve the conflicts there, then run 'git b finish' again."
        return 1
    fi
    if ! git tag -a "$version" -m "$type: $version"; then
        finish_rollback "$branch" "" "$main_before" || return 1
        return 1
    fi
    push_refs="$MAIN_BRANCH"

    # git flow: back-merge main into devBranch so the release (and its tag) are on it
    if [ "$TRUNK_MODE" -eq 0 ]; then
        if ! rb_pull_function "$DEV_BRANCH"; then
            finish_rollback "$branch" "$version" "$main_before" || return 1
            info "Rolled back; you are on '$branch'. Fix '$DEV_BRANCH' (see above), then run 'git b finish' again."

            return 1
        fi
        dev_before=$(git rev-parse "$DEV_BRANCH")

        if ! git merge --ff-only "$MAIN_BRANCH" 2>/dev/null && ! git merge --no-edit "$MAIN_BRANCH"; then
            err "back-merge of $MAIN_BRANCH into $DEV_BRANCH conflicted."
            if yes_no "Roll back the release merge and tag (then fix the cause and run 'git b finish' again)?"; then
                finish_rollback "$branch" "$version" "$main_before" "$dev_before" || return 1
                info "Rolled back. You are on '$branch' again."
            else
                info "Resolve the conflicts on $DEV_BRANCH and commit, then publish with:"
                info "  git push --atomic $REMOTE $MAIN_BRANCH $DEV_BRANCH refs/tags/$version && git b delete $branch"
            fi
            return 1
        fi
        push_refs="$MAIN_BRANCH $DEV_BRANCH"
    fi

    # push_refs must be unquoted
    # shellcheck disable=SC2086
    if ! git push --atomic "$REMOTE" $push_refs "refs/tags/$version"; then
        finish_push_failed "$branch" "$version" "$push_refs" "$main_before" "$dev_before"
        return 1
    fi

    delete_branch "$branch" || note "Kept branch '$branch'."
}

finish_branch() {
    local branch="${1:-$working_branch}"
    local type="topic"

    if [ -z "$branch" ]; then
        err "not on a branch; pass the branch to finish."
        return 1
    fi

    detect_protected_branch "fin_branch" "$branch" || return 1
    require_clean_tree || return 1
    sync_remote
    check_for_branch "$branch" || return 1
    check_for_branch "$MAIN_BRANCH" || return 1
    check_for_branch "$DEV_BRANCH" || return 1

    case "$branch" in
    "$RELEASE_PREFIX"*) type="release" ;;
    "$HOTFIX_PREFIX"*) type="hotfix" ;;
    esac

    rb_pull_function "$branch" || return 1

    if [ "$type" = "topic" ]; then
        finish_topic "$branch"
    else
        finish_release "$branch" "$type"
    fi
}

# Commits on <ref> that would be lost if every branch except main/devBranch
# (local and remote) and the current one went away. Prints nothing if merged.
unmerged_commits() {
    local ref="$1" branch="$2" keep="" r

    for r in "refs/heads/$MAIN_BRANCH" "refs/heads/$DEV_BRANCH" \
        "refs/remotes/$REMOTE/$MAIN_BRANCH" "refs/remotes/$REMOTE/$DEV_BRANCH"; do
        git rev-parse --verify --quiet "$r" >/dev/null && keep="$keep $r"
    done
    if [ "$(get_working_branch)" != "$branch" ]; then
        keep="$keep HEAD"
    fi
    # shellcheck disable=SC2086
    git rev-list --max-count=1 "$ref" --not $keep
}

# delete [branch] [-y] [-f]
#   -y  don't ask (only together with an explicit branch name)
#   -f  delete even if it has commits that aren't merged into main/devBranch
delete_branch() {
    local branch="" no_prompt="" force="" have_local="" ref question

    while [ "$#" -gt 0 ]; do
        case "$1" in
        -y | --yes | --y | -d | --d | --delete) no_prompt=1 ;;
        -f | --force | -D) force=1 ;;
        -*)
            err "unknown option: $1. usage: git b delete [branch] [-y] [-f]"
            return 1
            ;;
        *)
            if [ -z "$branch" ]; then
                branch="$1"
            else
                case "$1" in
                y | yes | d) no_prompt=1 ;;
                *)
                    err "too many arguments. usage: git b delete [branch] [-y] [-f]"
                    return 1
                    ;;
                esac
            fi
            ;;
        esac
        shift
    done
    if [ -z "$branch" ]; then
        branch="$working_branch"
        no_prompt="" # -y only skips the question when the branch is named
    fi
    if [ -z "$branch" ]; then
        err "not on a branch; pass the branch to delete."
        return 1
    fi

    detect_protected_branch "del_branch" "$branch" || return 1
    sync_remote

    if git rev-parse --verify --quiet "refs/heads/$branch" >/dev/null; then
        have_local=1
    elif ! remote_branch_exists "$branch"; then
        err "no branch '$branch' locally or on '$REMOTE'."
        return 1
    fi

    # Everything is checked before anything is switched or deleted
    if [ -z "$force" ]; then
        for ref in "refs/heads/$branch" "refs/remotes/$REMOTE/$branch"; do
            git rev-parse --verify --quiet "$ref" >/dev/null || continue
            if [ -n "$(unmerged_commits "$ref" "$branch")" ]; then
                err "'${ref#refs/*/}' has commits that aren't merged into $DEV_BRANCH or $MAIN_BRANCH."
                info "Delete it anyway with: git b delete $branch -f"
                return 1
            fi
        done
    fi
    if [ "$(get_working_branch)" = "$branch" ]; then
        require_clean_tree || return 1 # don't carry edits onto the dev branch
    fi

    if [ -z "$no_prompt" ]; then
        question="Delete '$branch' locally and on '$REMOTE'?"
        [ -n "$force" ] && question="Delete '$branch' locally and on '$REMOTE', including unmerged commits?"
        if ! yes_no "$question"; then
            info "Deletion aborted."
            return 1
        fi
    fi

    if [ "$(get_working_branch)" = "$branch" ]; then
        git switch "$DEV_BRANCH" || {
            err "failed to switch to $DEV_BRANCH (does it exist?)"
            return 1
        }
    fi
    if [ -n "$have_local" ]; then
        git branch -D "$branch" || return 1
    fi
    if remote_branch_exists "$branch"; then
        git push "$REMOTE" --delete "$branch" || warn "remote delete failed"
    fi
    info "Branch $branch deleted."
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
  finishTopic      $FINISH_TOPIC
  versionFile      ${VERSION_FILE:-(disabled)}
  protected        $MAIN_BRANCH $DEV_BRANCH ${EXTRA_PROTECTED}
EOF
}
