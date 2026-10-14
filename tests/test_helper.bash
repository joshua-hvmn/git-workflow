# Shared setup: every test gets a bare "remote" with main, next and a v1.0.0
# tag, plus a fresh clone to work in, and the default aliases (git b, git c,
# ...), so tests run commands the way people type them. Nothing touches your
# real git config.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
    # GIT_WORKFLOW_BIN runs the suite against an installed copy (make installcheck)
    export PATH="${GIT_WORKFLOW_BIN:-$REPO_ROOT/bin}:$PATH"
    export NO_COLOR=1
    # Never open an editor; a test that would is a failing test, not a hang
    export GIT_EDITOR=true GIT_SEQUENCE_EDITOR=true

    # Isolate from the developer's ~/.gitconfig (it may set workflow.* keys)
    # and ~/.config (where the alias sets go). HOME is a sibling of
    # XDG_CONFIG_HOME, so includes are written with their full path
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
    export XDG_CONFIG_HOME="$BATS_TEST_TMPDIR/config"
    export HOME="$BATS_TEST_TMPDIR/home"
    mkdir -p "$HOME"
    git config --global user.name "Test"
    git config --global user.email "test@example.com"
    git config --global init.defaultBranch main
    git config --global advice.detachedHead false
    # Most tests are about what finish does once it merges, so they merge
    # locally; the ones about pull requests (the default) unset this
    git config --global workflow.integrate merge
    git workflow aliases install >/dev/null 2>&1

    REMOTE_DIR="$BATS_TEST_TMPDIR/remote.git"
    SEED="$BATS_TEST_TMPDIR/seed"
    WORK="$BATS_TEST_TMPDIR/work"

    git init -q --bare "$REMOTE_DIR"
    git clone -q "$REMOTE_DIR" "$SEED" 2>/dev/null
    (
        cd "$SEED" || exit 1
        echo a >a
        echo b >b
        git add .
        git commit -qm init
        git tag -a v1.0.0 -m v1.0.0
        git push -q origin main main:next
        git push -q origin v1.0.0
    )
    git clone -q "$REMOTE_DIR" "$WORK"
    cd "$WORK" || return 1
}

# Make the local next branch exist (a fresh clone only has main)
local_next() {
    git switch -q next
    git switch -q main
}

# Commit a change to a file: commit_change <file> <message>
commit_change() {
    echo "$2" >>"$1"
    git add "$1"
    git commit -qm "$2"
}

# Advance a branch on the remote behind our back: remote_commit <branch> <file>
remote_commit() {
    (
        cd "$SEED" || exit 1
        git fetch -q origin
        git switch -q -C "$1" "origin/$1"
        echo upstream >>"$2"
        git commit -qam "upstream change on $1"
        AS_GITHUB=1 git push -q origin "$1"
    )
}

# Make the remote's main take changes only through pull requests: a push to
# it is rejected unless AS_GITHUB is set, which stands in for GitHub merging
# one (merge_pr) or for someone else's push (remote_commit). Local pushes run
# the hook with our environment, so the variable gets through.
protect_main() {
    # shellcheck disable=SC2016 # the generated script expands these
    {
        echo '#!/bin/sh'
        echo '[ -n "$AS_GITHUB" ] && exit 0'
        echo 'while read -r old new ref; do'
        echo '    if [ "$ref" = refs/heads/main ]; then'
        echo '        echo "protected branch: changes must be made through a pull request" >&2'
        echo '        exit 1'
        echo '    fi'
        echo 'done'
    } >"$REMOTE_DIR/hooks/pre-receive"
    chmod +x "$REMOTE_DIR/hooks/pre-receive"
}

# GitHub merging the pull request from <branch> into <base> (default main),
# with a merge commit or a squash, then deleting the branch:
# merge_pr <branch> [base] [merge|squash]
merge_pr() {
    local branch="$1" base="${2:-main}" how="${3:-merge}"
    (
        cd "$SEED" || exit 1
        git fetch -q origin
        git switch -q -C "$base" "origin/$base"
        if [ "$how" = squash ]; then
            git merge -q --squash "origin/$branch" >/dev/null
            git commit -qm "$branch (#1)"
        else
            git merge -q --no-ff --no-edit "origin/$branch"
        fi
        AS_GITHUB=1 git push -q origin "$base"
        AS_GITHUB=1 git push -q origin --delete "$branch"
    )
}

# A repository with no next branch: trunk / GitHub flow by default
drop_next() {
    git push -q origin --delete next
    git fetch -q --prune origin
}

# Work from a fork: origin is your fork (https://github.com/me/proj) and
# upstream the original (https://github.com/up/proj, which is remote.git).
# The URLs are GitHub-shaped, so gh gets owner names, but point at local
# repositories through url.<path>.insteadOf.
use_fork() {
    FORK_DIR="$BATS_TEST_TMPDIR/fork.git"
    git clone -q --bare "$REMOTE_DIR" "$FORK_DIR"
    git config --global url."$REMOTE_DIR".insteadOf https://github.com/up/proj.git
    git config --global url."$FORK_DIR".insteadOf https://github.com/me/proj.git
    git remote set-url origin https://github.com/me/proj.git
    git remote add upstream https://github.com/up/proj.git
    git fetch -q --all --prune
}

# Make the remote reject every push
reject_pushes() {
    printf '#!/bin/sh\necho "push rejected by test hook" >&2\nexit 1\n' >"$REMOTE_DIR/hooks/pre-receive"
    chmod +x "$REMOTE_DIR/hooks/pre-receive"
}

allow_pushes() {
    rm -f "$REMOTE_DIR/hooks/pre-receive"
}

remote_has_ref() {
    git ls-remote --exit-code "$REMOTE_DIR" "$1" >/dev/null
}

# Negated checks live in functions: a bare `! cmd` line never fails a bats
# test (set -e ignores it), but a function returning non-zero does.
remote_lacks_ref() {
    ! remote_has_ref "$1"
}

no_local_branch() {
    ! git rev-parse --verify --quiet "refs/heads/$1" >/dev/null
}

tag_exists_locally() {
    git show-ref --verify --quiet "refs/tags/$1"
}

no_local_tag() {
    ! tag_exists_locally "$1"
}

not_ancestor() {
    ! git merge-base --is-ancestor "$1" "$2"
}

no_merge_in_progress() {
    ! git rev-parse --verify --quiet MERGE_HEAD >/dev/null
}

# Put a fake `gh` first on PATH and use pull requests. `gh pr list` prints
# what its --jq would: $1, the "<STATE> <url>" of the newest pull request
# (gh_view changes it later), or with mergeCommit in the query, gh_merge's
# commit. Every other call is logged to $GH_LOG.
fake_gh() {
    local bin="$BATS_TEST_TMPDIR/bin"
    GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    GH_VIEW="$BATS_TEST_TMPDIR/gh.view"
    GH_MERGE="$BATS_TEST_TMPDIR/gh.merge"
    : >"$GH_LOG"
    : >"$GH_MERGE"
    gh_view "${1:-}"
    mkdir -p "$bin"
    # shellcheck disable=SC2016 # the generated script expands these
    {
        echo '#!/bin/sh'
        echo 'if [ "$1 $2" = "pr list" ]; then'
        echo '    case "$*" in'
        echo "    *mergeCommit*) cat '$GH_MERGE' ;;"
        echo "    *) cat '$GH_VIEW' ;;"
        echo '    esac'
        echo '    exit 0'
        echo 'fi'
        echo "echo \"\$*\" >>'$GH_LOG'"
    } >"$bin/gh"
    chmod +x "$bin/gh"
    export PATH="$bin:$PATH" GH_LOG GH_VIEW GH_MERGE
    use_prs
}

# Back to the default: finish opens pull requests
use_prs() {
    git config --global --unset workflow.integrate || :
}

gh_view() {
    printf '%s' "$1" >"$GH_VIEW"
}

gh_merge() {
    printf '%s' "$1" >"$GH_MERGE"
}

squash_editor() {
    local ed="$BATS_TEST_TMPDIR/squash_editor"
    # shellcheck disable=SC2016 # the generated script expands these
    printf '#!/bin/sh\nsed "2,\\$s/^pick/fixup/" "$1" >"$1.tmp" && mv "$1.tmp" "$1"\n' >"$ed"
    chmod +x "$ed"
    printf '%s' "$ed"
}

no_rebase_in_progress() {
    local dir
    dir=$(git rev-parse --git-dir)
    [ ! -d "$dir/rebase-merge" ] && [ ! -d "$dir/rebase-apply" ]
}
