# Shared setup: every test gets a bare "remote" with main, next and a v1.0.0
# tag, plus a fresh clone to work in. Nothing touches your real git config.

REPO_ROOT="$(cd "$(dirname "$BATS_TEST_FILENAME")/.." && pwd)"

setup() {
    export PATH="$REPO_ROOT/scripts:$PATH"
    unset GIT_SCRIPTS_HOME_DIR
    export NO_COLOR=1
    # Never open an editor; a test that would is a failing test, not a hang
    export GIT_EDITOR=true GIT_SEQUENCE_EDITOR=true

    # Isolate from the developer's ~/.gitconfig (it may set workflow.* keys)
    export GIT_CONFIG_NOSYSTEM=1
    export GIT_CONFIG_GLOBAL="$BATS_TEST_TMPDIR/gitconfig"
    git config --global user.name "Test"
    git config --global user.email "test@example.com"
    git config --global init.defaultBranch main
    git config --global advice.detachedHead false

    REMOTE_DIR="$BATS_TEST_TMPDIR/remote.git"
    SEED="$BATS_TEST_TMPDIR/seed"
    WORK="$BATS_TEST_TMPDIR/work"

    git init -q --bare "$REMOTE_DIR"
    git clone -q "$REMOTE_DIR" "$SEED" 2>/dev/null
    (
        cd "$SEED"
        echo a >a
        echo b >b
        git add .
        git commit -qm init
        git tag -a v1.0.0 -m v1.0.0
        git push -q origin main main:next
        git push -q origin v1.0.0
    )
    git clone -q "$REMOTE_DIR" "$WORK"
    cd "$WORK"
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
        cd "$SEED"
        git fetch -q origin
        git switch -q -C "$1" "origin/$1"
        echo upstream >>"$2"
        git commit -qam "upstream change on $1"
        git push -q origin "$1"
    )
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

not_ancestor() {
    ! git merge-base --is-ancestor "$1" "$2"
}

no_merge_in_progress() {
    ! git rev-parse --verify --quiet MERGE_HEAD >/dev/null
}

# Put a fake `gh` first on PATH. `gh pr view` prints $1 (an existing PR's URL)
# or fails when no URL is given; every other call is logged to $GH_LOG.
fake_gh() {
    local bin="$BATS_TEST_TMPDIR/bin"
    GH_LOG="$BATS_TEST_TMPDIR/gh.log"
    : >"$GH_LOG"
    mkdir -p "$bin"
    {
        echo '#!/bin/sh'
        echo 'if [ "$1 $2" = "pr view" ]; then'
        if [ -n "${1:-}" ]; then
            echo "    echo '$1'; exit 0"
        else
            echo '    exit 1'
        fi
        echo 'fi'
        echo "echo \"\$*\" >>'$GH_LOG'"
    } >"$bin/gh"
    chmod +x "$bin/gh"
    export PATH="$bin:$PATH" GH_LOG
}

squash_editor() {
    local ed="$BATS_TEST_TMPDIR/squash_editor"
    printf '#!/bin/sh\nsed "2,\\$s/^pick/fixup/" "$1" >"$1.tmp" && mv "$1.tmp" "$1"\n' >"$ed"
    chmod +x "$ed"
    printf '%s' "$ed"
}
