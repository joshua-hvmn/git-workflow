# shellcheck shell=bash
# Sourced by the git-workflow commands; not executable on its own.

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.

# Include guard to prevent redundant parsing
if [ -n "${__WF_FLOW_LOADED:-}" ]; then
    return 0
fi
__WF_FLOW_LOADED=1

if [ -z "${__WF_CORE_LOADED:-}" ]; then
    . "$GIT_WORKFLOW_DATADIR/core.sh"
fi
if [ -z "${__WF_RELEASE_LOADED:-}" ]; then
    . "$GIT_WORKFLOW_DATADIR/release.sh"
fi

WF_MERGED_HEAD=''

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
        git branch --quiet --track "$target_branch" "$(remote_ref "$target_branch")" || return 1
        note "Created local '$target_branch' tracking '$(remote_ref "$target_branch")'."
        return 0
    fi

    err "could not find branch '$target_branch' locally or on '$(remote_for "$target_branch")'."
    return 1
}

# branches_of_type <type> [except]: open branches of a (prefixed) type,
# local or remote
branches_of_type() {
    local pattern remote
    type_get "$1" || return 0
    [ -n "$T_PREFIX" ] || return 0
    pattern="$T_PREFIX"
    case "$pattern" in
    */) ;;
    *) pattern="$pattern*" ;;
    esac
    remote=$(remote_for "${T_PREFIX}x")
    {
        git for-each-ref --format='%(refname:short)' "refs/heads/$pattern"
        git for-each-ref --format='%(refname:lstrip=3)' "refs/remotes/$remote/$pattern"
    } | sort -u | grep -vxF "${2:-}" || true
}

# "release, hotfix and topic": this flow's branch types
types_list() {
    local t out="" n=0 count
    # shellcheck disable=SC2086 # a list
    count=$(printf '%s\n' $WF_TYPES | grep -c .)
    for t in $WF_TYPES; do
        n=$((n + 1))
        if [ -z "$out" ]; then
            out="$t"
        elif [ "$n" -eq "$count" ]; then
            out="$out and $t"
        else
            out="$out, $t"
        fi
    done
    printf '%s' "$out"
}

# start_type <word>: the branch type `start` was asked for. The 1.x/2.x
# spellings (t, -t, --topic, ...) still work for the types they named.
start_type() {
    local t
    for t in $WF_TYPES; do
        [ "$1" = "$t" ] && printf '%s' "$t" && return 0
    done
    case "$1" in
    t | -t | --topic) t=topic ;;
    r | -r | --release) t=release ;;
    h | -h | --hotfix) t=hotfix ;;
    *) return 1 ;;
    esac
    type_get "$t" || return 1
    printf '%s' "$t"
}

start_branch() {
    local mode="" name="" type full others base start_point prompt latest

    while [ "$#" -gt 0 ]; do
        case "$1" in
        -y | --yes) ASSUME_YES=1 ;;
        *)
            # The 1.x/2.x type spellings start with a dash too (-t, --topic)
            if [ -z "$mode" ]; then
                mode="$1"
            elif [ -z "$name" ]; then
                name="$1"
            else
                err "too many arguments. usage: $(wf_cmd branch start "<type> [name] [-y]")"
                return 1
            fi
            ;;
        esac
        shift
    done

    if [ -z "$mode" ]; then
        err "usage: $(wf_cmd branch start "<type> [name]"). Types in the $WF_FLOW flow: $(types_list)."
        return 1
    fi
    if ! type=$(start_type "$mode"); then
        err "the $WF_FLOW flow has no '$mode' branches. Its types: $(types_list)."
        if [ "$mode" = release ] && [ "$RELEASE_FROM_MAIN" = true ]; then
            info "It releases from $MAIN_BRANCH instead: on $MAIN_BRANCH, $(wf_cmd branch pre), test it, then $(wf_cmd branch release)."
        fi
        return 1
    fi
    type_get "$type"

    sync_remote
    case "$T_FROM" in
    latest-release)
        # main already has unreleased work, so the branch starts from the
        # release it fixes, or it would ship that work untested
        base=""
        start_point=$(latest_stable_tag)
        if [ -z "$start_point" ]; then
            err "there's no release to start a $type branch from yet (no $VFMT tag)."
            return 1
        fi
        ;;
    *)
        base=$(resolve_point "$T_FROM")
        start_point="$base"
        check_for_branch "$base" || return 1
        ;;
    esac

    prompt="Enter the new $type branch's name:"
    type_versioned "$type" && prompt="Enter the version ($VEX, or major, minor or patch):"
    get_user_input "$name" "$prompt" || return 1
    name="$REPLY"
    if type_versioned "$type"; then
        case "$name" in
        major | minor | patch)
            name=$(bump_version "$name")
            latest=$(latest_stable_tag)
            info "Next $REPLY version: $name${latest:+ (after $latest)}."
            ;;
        *) name=$(normalize_version "$name") ;;
        esac
    fi
    type_get "$type"
    full="$T_PREFIX$name"

    if [ "$(git check-ref-format --branch "$full" 2>/dev/null)" != "$full" ]; then
        err "'$full' is not a valid branch name."
        return 1
    fi

    if type_versioned "$type"; then
        validate_new_version "$name" || return 1
    fi

    type_get "$type"
    if [ "$T_SINGLE" = true ]; then
        others=$(branches_of_type "$type" "$full")
        if [ -n "$others" ]; then
            flow_warn "the $WF_FLOW flow has one $type branch at a time; already open: $(printf '%s' "$others" | tr '\n' ' ')" || return 1
        fi
    fi

    if git rev-parse --verify --quiet "refs/heads/$full" >/dev/null; then
        err "branch '$full' already exists."
        return 1
    fi

    if remote_branch_exists "$full"; then
        err "branch '$full' already exists on '$(remote_for "$full")'. Pick another name, or check it out: git switch $full"
        return 1
    fi

    info "Starting $type branch '$full' from '$start_point'..."
    if [ -n "$base" ]; then
        pull_branch "$base" || return 1
    fi
    git switch -c "$full" "$start_point" || return 1
    if type_versioned "$type"; then
        offer_version_commit "$name" ||
            note "Set $VERSION_FILE to $name and commit it before $(wf_cmd branch pre)."
    fi
    git push -u "$REMOTE" "$full"
}

# finish_rollback <branch> [tag] [<branch> <commit>]...
# Abort a half-done merge, delete the tag it made, put each named branch back
# where it was, and return to <branch>. Only local refs are touched.
finish_rollback() {
    local branch="$1" tag="${2:-}"
    shift 2 || shift $#

    if git rev-parse --verify --quiet MERGE_HEAD >/dev/null; then
        git merge --abort || return 1
    fi
    git switch --quiet "$branch" || return 1
    if [ -n "$tag" ]; then
        git tag -d "$tag" >/dev/null || return 1
    fi
    while [ "$#" -ge 2 ]; do
        if [ -n "$2" ]; then
            git branch -f "$1" "$2" || return 1
        fi
        shift 2
    done
}

# ---------------------------------------------------------------------------
# finish, with integrate=merge: merge locally, then one atomic push
# ---------------------------------------------------------------------------

# finish_versioned_checks <branch> <type> <version>: before a versioned
# branch is integrated, either way
finish_versioned_checks() {
    local branch="$1" type="$2" version="$3" last_pre t others

    validate_new_version "$version" || return 1
    check_version_file "$branch" "$version" finish || return 1

    if [ -z "$(prerelease_tags_for "$version")" ]; then
        note "No prereleases were cut for $version ($(wf_cmd branch pre)). Releasing untested artifacts."
    else
        note "Prereleases for $version: $(prerelease_tags_for "$version" | paste -sd ' ' -)"
        last_pre=$(prerelease_tags_for "$version" | tail -n 1)
        if [ "$(git rev-parse "$last_pre^{commit}")" != "$(git rev-parse "$branch")" ]; then
            flow_warn "'$branch' has commits after $last_pre that no prerelease tested." || return 1
        fi
    fi

    # A fix to a release (from main or a tag) that other open versioned
    # branches started before: they don't have it
    type_get "$type"
    if [ "$T_FROM" != dev ]; then
        for t in $WF_TYPES; do
            [ "$t" = "$type" ] && continue
            type_versioned "$t" || continue
            [ "$T_FROM" = dev ] || continue
            others=$(branches_of_type "$t")
            if [ -n "$others" ]; then
                warn "open $t branch(es) don't have this fix: $(printf '%s' "$others" | tr '\n' ' ')- merge it into them after this."
            fi
        done
    fi
}

finish_merge() {
    local branch="$1" type="$2" version="" into back="" into_before back_before="" tag_target question refs url
    type_get "$type"
    into=$(resolve_point "$T_INTO")
    if [ "$T_BACK" = dev ] && [ "$DEV_BRANCH" != "$into" ]; then
        back="$DEV_BRANCH"
    fi

    if type_versioned "$type"; then
        version=$(branch_version "$branch")
        finish_versioned_checks "$branch" "$type" "$version" || return 1
        type_get "$type"
        question="Merge '$branch' into $into${back:+ and $back}, tag $version, and push?"
    else
        question="Merge '$branch' into $into and push?"
    fi
    yes_no "$question" || {
        info "Aborted."
        return 1
    }

    if ! pull_branch "$into"; then
        git switch --quiet "$branch" 2>/dev/null || :
        return 1
    fi
    into_before=$(git rev-parse "$into")

    if [ -n "$version" ]; then
        git merge --no-ff --no-edit -m "Merge $type $version" "$branch"
    else
        git merge --no-ff --no-edit "$branch"
    fi || {
        err "merging '$branch' into '$into' conflicted."
        finish_rollback "$branch" "" "$into" "$into_before" || return 1
        info "Rolled back; you are on '$branch'. Bring in the latest '$into'"
        info "(git merge $(remote_ref "$into")), resolve the conflicts there, then run '$(wf_cmd branch finish)' again."
        return 1
    }

    if [ -n "$version" ]; then
        # merge: what main now has. tip: the commit the prereleases tested
        # (main may have moved on since the branch started)
        type_get "$type"
        tag_target=HEAD
        [ "$T_TAG" = tip ] && tag_target="$branch"
        if ! not_released "$tag_target" || ! git tag -a "$version" -m "$type: $version" "$tag_target"; then
            finish_rollback "$branch" "" "$into" "$into_before" || return 1
            return 1
        fi
    fi
    refs="$into"

    # Back-merge, so the release (and its tag) are on the dev branch too
    if [ -n "$back" ]; then
        if ! pull_branch "$back"; then
            finish_rollback "$branch" "$version" "$into" "$into_before" || return 1
            info "Rolled back; you are on '$branch'. Fix '$back' (see above), then run '$(wf_cmd branch finish)' again."
            return 1
        fi
        back_before=$(git rev-parse "$back")

        if ! git merge --ff-only "$into" 2>/dev/null && ! git merge --no-edit "$into"; then
            err "back-merge of $into into $back conflicted."
            if yes_no "Roll back the merge${version:+ and tag} (then fix the cause and run '$(wf_cmd branch finish)' again)?"; then
                finish_rollback "$branch" "$version" "$into" "$into_before" "$back" "$back_before" || return 1
                info "Rolled back. You are on '$branch' again."
            else
                info "Resolve the conflicts on $back and commit, then publish with:"
                info "  git push --atomic $UPSTREAM $into $back${version:+ refs/tags/$version} && $(wf_cmd branch delete "$branch")"
            fi
            return 1
        fi
        refs="$into $back"
    fi

    # Everything or nothing. Only this one tag: --tags would publish any stray
    # local tag, and GitHub skips workflow runs when more than three tags
    # arrive in one push.
    # shellcheck disable=SC2086 # refs is a list
    if ! git push --atomic "$UPSTREAM" $refs ${version:+"refs/tags/$version"}; then
        err "push to '$UPSTREAM' was rejected; nothing was published."
        if [ -z "$version" ]; then
            finish_rollback "$branch" "" "$into" "$into_before" || return 1
            info "Rolled back; you are on '$branch'. If someone pushed to '$into' first, run '$(wf_cmd branch finish)' again."
            info "If '$into' only accepts pull requests: git config workflow.$type.integrate pr"
            return 1
        fi
        info "Locally, $refs and tag $version are ahead of '$UPSTREAM'. To retry the push:"
        info "  git push --atomic $UPSTREAM $refs refs/tags/$version && $(wf_cmd branch delete "$branch")"
        if yes_no "Roll back the local merge and tag instead (then fix the cause and run '$(wf_cmd branch finish)' again)?"; then
            finish_rollback "$branch" "$version" "$into" "$into_before" "$back" "$back_before" || return 1
            info "Rolled back. You are on '$branch' again."
        fi
        return 1
    fi

    if [ -n "$version" ]; then
        note "Released '$version'."
        url=$(actions_url)
        [ -n "$url" ] && note "Watch the release run: $url  (or: gh run watch)"
    fi
    delete_branch "$branch" || note "Kept branch '$branch'."
}

# ---------------------------------------------------------------------------
# finish, with integrate=pr: open a pull request; run finish again once it's
# merged, and it tags (versioned types) and cleans up
# ---------------------------------------------------------------------------

# Load the forge (workflow.forge) the first time it's needed
forge_load() {
    if [ -z "${__WF_FORGE_LOADED:-}" ]; then
        # shellcheck source=/dev/null # each forge is checked on its own
        . "$GIT_WORKFLOW_DATADIR/forges/$FORGE.sh" || return 1
        __WF_FORGE_LOADED=1
    fi
    forge_require
}

# True when <ref>'s changes are already on <into> as different commits: a
# pull request merged by rebase (each commit has an equivalent) or by squash
# (one commit with the same change as the whole branch).
content_merged() {
    local ref="$1" into="$2" base squash

    if ! git cherry "$into" "$ref" | grep -q '^+'; then
        return 0
    fi
    base=$(git merge-base "$into" "$ref") || return 1
    squash=$(git commit-tree "$ref^{tree}" -p "$base" -m squash 2>/dev/null) || return 1
    case "$(git cherry "$into" "$squash")" in
    -*) return 0 ;;
    esac
    return 1
}

# merge_point <tip> <ref>: the commit on <ref>'s first-parent line that brought
# <tip> in (the merge commit, or <tip> itself after a fast-forward)
merge_point() {
    local tip="$1" ref="$2" last
    tip=$(git rev-parse "$tip^{commit}") || return 1
    last=$(git rev-list --first-parent --ancestry-path "$tip..$ref" | tail -n 1)
    if [ -z "$last" ] || [ "$(git rev-parse "$last^")" = "$tip" ]; then
        last="$tip"
    fi
    printf '%s' "$last"
}

# A merged branch: delete it, then bring the dev branch, where deleting the
# current branch leaves you, up to date with what was merged
finish_cleanup() {
    delete_branch "$1" || {
        note "Kept branch '$1'."
        return 0
    }
    if [ "$(get_working_branch)" = "$DEV_BRANCH" ]; then
        pull_branch "$DEV_BRANCH"
    fi
}

finish_pr() {
    local branch="$1" type="$2" version="" into into_ref back="" how="" state="" url="" target title body url_actions remote head
    type_get "$type"
    into=$(resolve_point "$T_INTO")
    into_ref=$(remote_ref "$into")
    remote=$(remote_for "$branch")
    if [ "$T_BACK" = dev ] && [ "$DEV_BRANCH" != "$into" ]; then
        back="$DEV_BRANCH"
    fi
    if type_versioned "$type"; then
        version=$(branch_version "$branch")
        finish_versioned_checks "$branch" "$type" "$version" || return 1
        type_get "$type"
    fi

    # Merged already? A merge commit keeps the branch's commits; a squash or
    # rebase only their changes
    if remote_branch_exists "$into" && git merge-base --is-ancestor "$branch" "$into_ref"; then
        # ...unless the branch has no commits of its own: then its tip is a
        # commit on $into's own line (it was just started), not a merged one
        if [ "$(merge_point "$branch" "$into_ref")" = "$(git rev-parse "$branch")" ]; then
            err "'$branch' has no commits that '$into_ref' doesn't already have; there's nothing to finish."
            return 1
        fi
        how=commit
    elif remote_branch_exists "$into" && content_merged "$branch" "$into_ref"; then
        how=changes
    fi
    if [ -z "$how" ]; then
        forge_load || return 1
        state=$(forge_pr_find "$branch" "$remote") || {
            err "couldn't look up the pull requests for '$branch' with $(forge_name) (see above)."
            return 1
        }
        url="${state#* }"
        case "$state" in
        MERGED\ *)
            # gh knows it merged, but git can't tell (squashed after nearby
            # lines changed). Unless this branch has commits that pull request
            # never had: a branch name used again after its pull request merged.
            head=$(forge_pr_head "$branch" "$remote") || head=""
            if [ -z "$head" ] || ! git cat-file -e "$head^{commit}" 2>/dev/null; then
                how=changes
            elif git merge-base --is-ancestor "$branch" "$head"; then
                how=changes
                WF_MERGED_HEAD="$head" # delete_branch counts everything up to it as merged
            else
                note "The last pull request from '$branch' merged without its newest commits: $url"
                state="" url=""
            fi
            ;;
        esac
    fi

    if [ -n "$how" ] && [ -z "$version" ]; then
        note "'$branch' is merged into '$into_ref'${url:+: $url}"
        finish_cleanup "$branch"
        return
    fi

    if [ -n "$how" ]; then
        # The tag: tip needs the tested commit itself on main
        type_get "$type"
        if [ "$T_TAG" = tip ]; then
            if [ "$how" != commit ]; then
                err "'$branch' was merged into '$into_ref' as a squash or rebase${url:+ ($url)}, so the commit your prereleases tested isn't on $into, and tagging it would release code $into doesn't have."
                if [ "$RELEASE_FROM_MAIN" = true ]; then
                    info "Release from $into instead: on $into, $(wf_cmd branch pre "$version"), test it, then $(wf_cmd branch release "$version")."
                else
                    info "Merge it with a merge commit next time. For this one, tag the commit on $into by hand: git tag -a $version -m $version <commit> && git push $UPSTREAM refs/tags/$version"
                fi
                return 1
            fi
            target=$(git rev-parse "$branch") || return 1
        elif [ "$how" = commit ]; then
            target=$(merge_point "$branch" "$into_ref") || return 1
        else
            forge_load || return 1
            target=$(forge_pr_merge_commit "$branch" "$remote") || target=""
            if [ -z "$target" ] || ! git merge-base --is-ancestor "$target" "$into_ref" 2>/dev/null; then
                err "'$branch' was squash- or rebase-merged, and $(forge_name) didn't give a merge commit on '$into_ref' to tag."
                return 1
            fi
        fi

        not_released "$target" || return 1
        yes_no "'$branch' is merged into '$into_ref'. Tag $(git rev-parse --short "$target") $version and push the tag?" || {
            info "Aborted."
            return 1
        }
        tag_and_push "$version" "$target" "$type: $version" || return 1
        note "Released '$version'."
        url_actions=$(actions_url)
        [ -n "$url_actions" ] && note "Watch the release run: $url_actions  (or: gh run watch)"

        # Back-merge through a pull request too
        if [ -n "$back" ] && remote_branch_exists "$back" &&
            ! git merge-base --is-ancestor "$target" "$(remote_ref "$back")"; then
            forge_load || return 1
            state=$(forge_pr_find "$into" "$UPSTREAM") || state=""
            case "$state" in
            OPEN\ *) note "Bring $version into $back with the open pull request from $into: ${state#* }" ;;
            *)
                if yes_no "Open a pull request from '$into' into '$back', so $version is on $back too?" "y"; then
                    forge_pr_create "$back" "$into" "$UPSTREAM" "Merge $into into $back after $version" \
                        "Back-merge of $version. Merge it with a merge commit, so $back has the release and its tag." || return 1
                fi
                ;;
            esac
        fi
        finish_cleanup "$branch"
        return
    fi

    # Not merged yet: publish it and open (or show) the pull request
    case "$state" in
    OPEN\ *)
        git push -u "$remote" "$branch" || return 1
        note "A pull request for '$branch' is already open: $url"
        return 0
        ;;
    CLOSED\ *)
        note "The last pull request for '$branch' was closed without merging: $url"
        ;;
    esac
    yes_no "Open a pull request from '$branch' into '$into'?" "y" || {
        info "Aborted."
        return 1
    }
    git push -u "$remote" "$branch" || return 1
    title="" body=""
    if [ -n "$version" ]; then
        type_get "$type"
        title="$(printf '%s' "${type:0:1}" | tr '[:lower:]' '[:upper:]')${type:1} $version"
        if [ "$T_TAG" = tip ]; then
            body="Merge with a merge commit, not squash or rebase: once it's merged, \`$(wf_cmd branch finish "$branch")\` tags this branch's tested tip as $version."
        else
            body="Once it's merged, \`$(wf_cmd branch finish "$branch")\` tags the merge as $version."
        fi
    fi
    forge_pr_create "$into" "$branch" "$remote" "$title" "$body" || return 1
    if [ -n "$version" ]; then
        type_get "$type"
        if [ "$T_TAG" = tip ]; then
            info "Merge it with a merge commit (not squash or rebase), then run '$(wf_cmd branch finish "$branch")' to tag $version."
        else
            info "Once it's merged, run '$(wf_cmd branch finish "$branch")' to tag $version."
        fi
    else
        info "Once it's merged, '$(wf_cmd branch finish "$branch")' deletes the branch."
    fi
}

finish_branch() {
    local branch="" type

    while [ "$#" -gt 0 ]; do
        case "$1" in
        -y | --yes) ASSUME_YES=1 ;;
        -*)
            err "unknown option: $1. usage: $(wf_cmd branch finish "[branch] [-y]")"
            return 1
            ;;
        *)
            if [ -n "$branch" ]; then
                err "too many arguments. usage: $(wf_cmd branch finish "[branch] [-y]")"
                return 1
            fi
            branch="$1"
            ;;
        esac
        shift
    done
    branch="${branch:-$working_branch}"

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

    type=$(branch_type "$branch")
    if [ -z "$type" ]; then
        err "'$branch' isn't a branch of any type in the $WF_FLOW flow ($(types_list))."
        return 1
    fi

    pull_branch "$branch" || return 1

    type_get "$type"
    if [ "$T_INTEGRATE" = pr ]; then
        finish_pr "$branch" "$type"
    else
        finish_merge "$branch" "$type"
    fi
}

# Commits on <ref> that would be lost if every branch except main/devBranch
# (local and remote) and the current one went away. Prints nothing if merged,
# including squash- and rebase-merged pull requests.
unmerged_commits() {
    local ref="$1" branch="$2" keep="" r b left

    # Everything in a pull request the forge says merged (finish_pr sets it)
    if [ -n "$WF_MERGED_HEAD" ] && git merge-base --is-ancestor "$ref" "$WF_MERGED_HEAD" 2>/dev/null; then
        return 0
    fi
    for b in "$MAIN_BRANCH" "$DEV_BRANCH"; do
        for r in "refs/heads/$b" "refs/remotes/$(remote_ref "$b")"; do
            git rev-parse --verify --quiet "$r" >/dev/null && keep="$keep $r"
        done
    done
    if [ "$(get_working_branch)" != "$branch" ]; then
        keep="$keep HEAD"
    fi
    # shellcheck disable=SC2086
    left=$(git rev-list --max-count=1 "$ref" --not $keep)
    [ -n "$left" ] || return 0
    for r in $keep; do
        [ "$r" = HEAD ] && continue
        content_merged "$ref" "$r" && return 0
    done
    printf '%s\n' "$left"
}

# "next or main", or just "main" when they're the same
merge_targets() {
    if [ "$DEV_BRANCH" = "$MAIN_BRANCH" ]; then
        printf '%s' "$MAIN_BRANCH"
    else
        printf '%s or %s' "$DEV_BRANCH" "$MAIN_BRANCH"
    fi
}

# delete [branch] [-y] [-f]
#   -y  don't ask (only together with an explicit branch name)
#   -f  delete even if it has commits that aren't merged into main/devBranch
delete_branch() {
    local branch="" no_prompt="" force="" have_local="" ref question

    while [ "$#" -gt 0 ]; do
        case "$1" in
        -y | --yes) no_prompt=1 ;;
        --y | -d | --d | --delete)
            # 1.x spellings. -d reads as git branch -d (delete if merged),
            # the opposite of "don't ask"
            warn "'$1' is deprecated and goes away in v4; use -y, or --yes."
            no_prompt=1
            ;;
        -f | --force | -D) force=1 ;;
        -*)
            err "unknown option: $1. usage: $(wf_cmd branch delete "[branch] [-y] [-f]")"
            return 1
            ;;
        *)
            if [ -z "$branch" ]; then
                branch="$1"
            else
                case "$1" in
                y | yes | d)
                    warn "'$1' after the branch name is deprecated and goes away in v4; use -y, or --yes."
                    no_prompt=1
                    ;;
                *)
                    err "too many arguments. usage: $(wf_cmd branch delete "[branch] [-y] [-f]")"
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
        err "no branch '$branch' locally or on '$(remote_for "$branch")'."
        return 1
    fi

    # Everything is checked before anything is switched or deleted
    if [ -z "$force" ]; then
        for ref in "refs/heads/$branch" "refs/remotes/$(remote_ref "$branch")"; do
            git rev-parse --verify --quiet "$ref" >/dev/null || continue
            if [ -n "$(unmerged_commits "$ref" "$branch")" ]; then
                err "'${ref#refs/*/}' has commits that aren't merged into $(merge_targets)."
                info "Delete it anyway with: $(wf_cmd branch delete "$branch" -f)"
                return 1
            fi
        done
    fi
    if [ "$(get_working_branch)" = "$branch" ]; then
        require_clean_tree || return 1 # don't carry edits onto the dev branch
    fi

    if [ -z "$no_prompt" ]; then
        question="Delete '$branch' locally and on '$(remote_for "$branch")'?"
        [ -n "$force" ] && question="Delete '$branch' locally and on '$(remote_for "$branch")', including unmerged commits?"
        if ! yes_no "$question"; then
            info "Deletion aborted."
            return 1
        fi
    fi

    if [ "$(get_working_branch)" = "$branch" ]; then
        # Quietly: git's "use git pull" hint would be wrong after a merged pull
        # request, since finish brings it up to date right after
        git switch --quiet "$DEV_BRANCH" || {
            err "failed to switch to $DEV_BRANCH (does it exist?)"
            return 1
        }
    fi
    if [ -n "$have_local" ]; then
        git branch -D "$branch" || return 1
    fi
    if remote_branch_exists "$branch"; then
        git push "$(remote_for "$branch")" --delete "$branch" || warn "remote delete failed"
    fi
    info "Branch $branch deleted. You're on $(get_working_branch)."
}

# show_config [--types | --versioned-types]: the effective settings, and
# where each came from. --types prints only the branch type names, and
# --versioned-types the ones named by version (for tab completion).
show_config() {
    local t from into how tag extra
    case "${1:-}" in
    --types)
        # shellcheck disable=SC2086 # a list
        printf '%s\n' $WF_TYPES
        return 0
        ;;
    --versioned-types)
        for t in $WF_TYPES; do
            type_versioned "$t" && printf '%s\n' "$t"
        done
        return 0
        ;;
    esac

    cat <<EOF
git-workflow settings (git config workflow.<key>, or a .gitworkflow file):
  flow             $WF_FLOW  ($WF_FLOW_WHY)$(conf_get description && [ -n "$CONF_VAL" ] && printf '\n                   %s' "$CONF_VAL")
  mainBranch       $MAIN_BRANCH$(__cfg_src mainbranch)
  devBranch        $DEV_BRANCH$(__cfg_src devbranch)
  integrate        $INTEGRATE$(__cfg_src integrate)
  releaseFromMain  $RELEASE_FROM_MAIN$(__cfg_src releasefrommain)
  remote           $REMOTE$(__cfg_src remote)
  upstream         $UPSTREAM$(__cfg_src upstream)
  forge            $FORGE$(__cfg_src forge)
  prereleaseLabel  $PRERELEASE_LABEL$(__cfg_src prereleaselabel)
  strict           $STRICT$(__cfg_src strict)
  versionFile      ${VERSION_FILE:-(disabled)}$(__cfg_src versionfile)
  tagPrefix        ${TAG_PREFIX:-(none)}$(__cfg_src tagprefix)
  protected        $MAIN_BRANCH$([ "$DEV_BRANCH" != "$MAIN_BRANCH" ] && printf ' %s' "$DEV_BRANCH")${EXTRA_PROTECTED}
EOF
    [ -n "$WF_REPO_FILE" ] && printf '  repository file  %s\n' "$WF_REPO_FILE"

    printf '\nbranch types (workflow.<type>.<key>):\n'
    for t in $WF_TYPES; do
        type_get "$t"
        from="$T_FROM"
        [ "$from" = latest-release ] || from=$(resolve_point "$T_FROM")
        into=$(resolve_point "$T_INTO")
        how="merge"
        [ "$T_INTEGRATE" = pr ] && how="pull request"
        tag=""
        case "$T_TAG" in
        merge) tag=", tags $VFMT on the merge" ;;
        tip) tag=", tags $VFMT on its tested tip" ;;
        esac
        extra=""
        [ "$T_BACK" = dev ] && [ "$DEV_BRANCH" != "$into" ] && extra="$extra, merged back into $DEV_BRANCH"
        [ "$T_SINGLE" = true ] && extra="$extra, one at a time"
        printf '  %-9s %-11s from %s into %s by %s%s%s\n' "$t" "${T_PREFIX:-(no prefix)}" \
            "$from" "$into" "$how" "$tag" "$extra"
    done
}

# "  (<source>)" for a setting some layer set; nothing for a default
__cfg_src() {
    if conf_get "$1"; then
        printf '  (%s)' "$CONF_SRC"
    fi
}
