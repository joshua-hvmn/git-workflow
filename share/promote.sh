# shellcheck shell=bash
# Sourced by the git-workflow commands; not executable on its own.

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.
#
# Environment branches (workflow.environments) and `git workflow branch
# promote`: mainBranch, then each environment, in order (main -> staging ->
# production). Work only moves down the chain, and each environment gets
# exactly what the one before it tested: a promotion fast-forwards it, or,
# when it can't, makes a merge commit with the tested tree, and never puts a
# combination on it that nothing above it had.

# Include guard to prevent redundant parsing
if [ -n "${__WF_PROMOTE_LOADED:-}" ]; then
    return 0
fi
__WF_PROMOTE_LOADED=1

if [ -z "${__WF_FLOW_LOADED:-}" ]; then
    . "$GIT_WORKFLOW_DATADIR/flow.sh"
fi

# env_state <environment> <source>: how <environment> on UPSTREAM stands
# against <source>, the branch it's promoted from. Fails when <source> isn't
# on UPSTREAM. Sets:
#   ENV_MISSING  1: the environment isn't on UPSTREAM yet
#   ENV_OWN      1: it has changes <source> doesn't (a hotfix not merged back)
#   ENV_BEHIND   the commits <source> has that it doesn't
#   ENV_AT       the <source> commit it matches (for counting from)
#
# An environment it was promoted to by a merge or a squash has commits of its
# own, but no changes: its tree is the tree <source> had then. So it's matched
# by tree first, then by its changes (content_merged), and only then counts as
# having changes of its own.
env_state() {
    local env_ref="refs/remotes/$UPSTREAM/$1" src_ref="refs/remotes/$UPSTREAM/$2" base tree c t
    ENV_MISSING='' ENV_OWN='' ENV_BEHIND=0 ENV_AT=''
    git rev-parse --verify --quiet "$src_ref" >/dev/null || return 1
    if ! git rev-parse --verify --quiet "$env_ref" >/dev/null; then
        ENV_MISSING=1
        return 0
    fi
    if git merge-base --is-ancestor "$env_ref" "$src_ref"; then
        ENV_AT=$(git rev-parse "$env_ref")
    else
        base=$(git merge-base "$env_ref" "$src_ref") || base=''
        tree=$(git rev-parse "$env_ref^{tree}")
        if [ -n "$base" ]; then
            # Newest first, so the latest state of <source> it matches
            while read -r c t; do
                if [ "$t" = "$tree" ]; then
                    ENV_AT="$c"
                    break
                fi
            done < <(git log --format='%H %T' "$base..$src_ref" && git log -1 --format='%H %T' "$base")
        fi
        if [ -z "$ENV_AT" ]; then
            if [ -n "$base" ] && content_merged "$env_ref" "$src_ref"; then
                ENV_AT="$base"
            else
                ENV_OWN=1
                return 0
            fi
        fi
    fi
    ENV_BEHIND=$(git rev-list --count "$ENV_AT..$src_ref")
}

# Bring a local copy of <branch> to <commit>, if it has nothing of its own
__promote_update_local() {
    local b="$1" new="$2"
    git rev-parse --verify --quiet "refs/heads/$b" >/dev/null || return 0
    if ! git merge-base --is-ancestor "refs/heads/$b" "$new"; then
        note "Your local '$b' has commits of its own; left it as it is."
        return 0
    fi
    if [ "$(get_working_branch)" = "$b" ]; then
        git merge --ff-only --quiet "$new" || note "Bring your local '$b' up to date with: $(wf_cmd sync)"
    else
        git branch -f "$b" "$new" >/dev/null
    fi
}

promote_usage() {
    local b
    b=$(wf_cmd branch)
    cat <<EOF
usage: $b promote [environment] [-n|--dry-run] [-y|--yes]

Move an environment branch up to the branch before it: $MAIN_BRANCH${ENVIRONMENTS:+ -> ${ENVIRONMENTS// / -> }}.
With pull requests (workflow.integrate pr), it opens one; otherwise it
fast-forwards the environment and pushes it. It refuses an environment that
has changes the branch before it doesn't, since the result would be untested.

  $b promote              -> the first environment that's behind
  $b promote production   -> that one
  $b promote -n           -> show what would be promoted, change nothing
EOF
}

# git workflow branch promote [environment] [-n] [-y]
promote_branch() {
    local mode="create" env="" e src src_ref env_ref sha new what state url how
    while [ "$#" -gt 0 ]; do
        case "$1" in
        -n | --dry-run) mode="dry" ;;
        -y | --yes) ASSUME_YES=1 ;;
        -h | --help)
            promote_usage
            return 0
            ;;
        -*)
            err "unknown option: $1"
            promote_usage >&2
            return 1
            ;;
        *)
            if [ -n "$env" ]; then
                err "too many arguments."
                promote_usage >&2
                return 1
            fi
            env="$1"
            ;;
        esac
        shift
    done

    if [ -z "$ENVIRONMENTS" ]; then
        err "the $WF_FLOW flow has no environment branches to promote (workflow.environments)."
        return 1
    fi
    if [ -n "$env" ] && ! is_environment "$env"; then
        err "'$env' isn't an environment branch. The environments: $ENVIRONMENTS."
        return 1
    fi

    sync_remote

    # No environment named: the first one there's something to do for
    if [ -z "$env" ]; then
        for e in $ENVIRONMENTS; do
            env_state "$e" "$(env_source "$e")" || continue
            if [ -n "$ENV_MISSING$ENV_OWN" ] || [ "$ENV_BEHIND" -gt 0 ]; then
                env="$e"
                break
            fi
        done
        if [ -z "$env" ]; then
            note "Every environment is up to date: $MAIN_BRANCH -> ${ENVIRONMENTS// / -> }."
            return 0
        fi
    fi

    src=$(env_source "$env")
    src_ref="refs/remotes/$UPSTREAM/$src"
    env_ref="refs/remotes/$UPSTREAM/$env"
    if ! env_state "$env" "$src"; then
        err "'$src' isn't on '$UPSTREAM' yet, so there's nothing to promote to '$env'."
        is_environment "$src" && info "Promote it first: $(wf_cmd branch promote "$src")"
        return 1
    fi
    sha=$(git rev-parse --short "$src_ref")

    if [ -n "$ENV_MISSING" ]; then
        if [ "$mode" = dry ]; then
            info "Would create '$env' at $src's $sha ($(git log -1 --format=%s "$src_ref")) and push it to '$UPSTREAM'."
            return 0
        fi
        yes_no "'$env' isn't on '$UPSTREAM' yet. Create it at $src's $sha ($(git log -1 --format=%s "$src_ref")) and push it?" || {
            info "Aborted."
            return 1
        }
        git push "$UPSTREAM" "$(git rev-parse "$src_ref"):refs/heads/$env" || return 1
        note "Created '$env' at $sha."
        return 0
    fi

    if [ -n "$ENV_OWN" ]; then
        err "'$env' has changes '$src' doesn't, so promoting would put a combination on $env that $src never tested:"
        git log --oneline --no-merges "$src_ref..$env_ref" | head -n 5 >&2
        info "Merge $env into $src first (finishing a hotfix does that), then promote."
        return 1
    fi

    if [ "$ENV_BEHIND" -eq 0 ]; then
        note "'$env' is up to date with '$src' ($sha)."
        return 0
    fi

    how="merge"
    if [ "$INTEGRATE" = pr ] || pr_only_branch "$env"; then
        how="pr"
    fi

    if [ "$mode" = dry ]; then
        if [ "$how" = pr ]; then
            info "Would open a pull request promoting $(count_commits "$ENV_BEHIND") from '$src' into '$env', up to $sha:"
        else
            info "Would move '$env' to $src's $sha and push it, promoting $(count_commits "$ENV_BEHIND"):"
        fi
        git log --oneline --no-merges "$ENV_AT..$src_ref" | head -n 10 >&2
        return 0
    fi

    if [ "$how" = pr ]; then
        forge_load || return 1
        state=$(forge_pr_find "$src" "$UPSTREAM" "$env") || {
            err "couldn't look up the pull requests from '$src' with $(forge_name) (see above)."
            return 1
        }
        case "$state" in
        OPEN\ *)
            note "A pull request promoting '$src' to '$env' is already open: ${state#* }"
            return 0
            ;;
        esac
        yes_no "Open a pull request from '$src' into '$env', promoting $(count_commits "$ENV_BEHIND") up to $sha?" "y" || {
            info "Aborted."
            return 1
        }
        forge_pr_create "$env" "$src" "$UPSTREAM" "Promote $src to $env" \
            "Moves $env to what $src has, up to $sha. Merge it as it is, with nothing on top, so $env gets exactly what $src tested." || return 1
        info "Once it's merged, $env has $src's $sha."
        return 0
    fi

    # A fast-forward when the environment is part of the source's history;
    # otherwise (it was promoted by a merge or squash before) a merge commit
    # whose tree is exactly the source's, so nothing untested comes along
    if git merge-base --is-ancestor "$env_ref" "$src_ref"; then
        new=$(git rev-parse "$src_ref")
        what="fast-forward $env to $sha"
    else
        new=$(git commit-tree "$src_ref^{tree}" -p "$env_ref" -p "$src_ref" -m "Promote $src to $env") || return 1
        what="merge $src's $sha into $env, with exactly $src's tree"
    fi
    yes_no "Promote $(count_commits "$ENV_BEHIND") from '$src' to '$env' ($what) and push?" || {
        info "Aborted."
        return 1
    }
    if ! git push "$UPSTREAM" "$new:refs/heads/$env"; then
        err "push to '$UPSTREAM' was rejected; '$env' is as it was."
        info "If someone changed '$env' first, run '$(wf_cmd branch promote "$env")' again."
        return 1
    fi
    note "Promoted '$src' to '$env': $env is $(git rev-parse --short "$new") now."
    __promote_update_local "$env" "$new"
    url=$(ci_hint)
    [ -n "$url" ] && note "Watch the deploy run: $url"
    return 0
}
