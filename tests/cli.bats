#!/usr/bin/env bats
# The git workflow program itself: dispatch, help, and the alias sets.

load test_helper

ALIAS_DIR() { printf '%s' "$XDG_CONFIG_HOME/git-workflow/aliases"; }

include_count() {
    git config --global --get-all include.path | grep -cxF "$1" || true
}

# Put a fake `man` first on PATH that prints what it was asked for
fake_man() {
    local bin="$BATS_TEST_TMPDIR/bin"
    mkdir -p "$bin"
    printf '#!/bin/sh\necho "man $*"\n' >"$bin/man"
    chmod +x "$bin/man"
    export PATH="$bin:$PATH"
}

# --- dispatch -----------------------------------------------------------------

@test "commands run by name, and by their 1.x short name, with no aliases" {
    git workflow aliases remove >/dev/null 2>&1
    local_next
    run git workflow branch start topic foo
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "foo" ]
    run git workflow b start topic bar
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "bar" ]
    commit_change a "work"
    run git workflow ps
    [ "$status" -eq 0 ]
    remote_has_ref refs/heads/bar
}

@test "an unknown command fails and points at help" {
    run git workflow frobnicate
    [ "$status" -ne 0 ]
    [[ "$output" == *"'frobnicate' is not a git workflow command"* ]]
    [[ "$output" == *"git workflow help"* ]]
}

@test "no command prints the usage and fails; help prints it and succeeds" {
    run git workflow
    [ "$status" -ne 0 ]
    [[ "$output" == *"usage: git workflow <command>"* ]]

    run git workflow help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage: git workflow <command>"* ]]
}

@test "help shows your alias for each command" {
    git config --global alias.br "workflow branch"
    run git workflow help
    [[ "$output" =~ branch\ +git\ b\  ]]
    [[ "$output" =~ squash\ +git\ sq\  ]]

    git workflow aliases remove >/dev/null 2>&1
    run git workflow help
    [[ "$output" =~ branch\ +git\ br\  ]]
    [[ "$output" != *"git sq"* ]]
}

@test "version prints the VERSION file" {
    run git workflow version
    [ "$output" = "git-workflow $(cat "$REPO_ROOT/VERSION")" ]
    run git workflow --version
    [ "$output" = "git-workflow $(cat "$REPO_ROOT/VERSION")" ]
}

@test "--help and help <command> open the command's man page" {
    fake_man
    run git workflow b --help
    [ "$output" = "man git-workflow-branch" ]
    run git workflow help sq
    [ "$output" = "man git-workflow-squash" ]
    run git workflow help nope
    [ "$status" -ne 0 ]
}

# --- aliases --------------------------------------------------------------------

@test "aliases install: copies both sets to ~/.config and includes each once" {
    [ -f "$(ALIAS_DIR)/commands" ]
    [ -f "$(ALIAS_DIR)/extras" ]
    cmp "$REPO_ROOT/share/aliases/commands" "$(ALIAS_DIR)/commands"

    run git workflow aliases install
    [ "$status" -eq 0 ]
    [ "$(include_count "$(ALIAS_DIR)/commands")" -eq 1 ]
    [ "$(include_count "$(ALIAS_DIR)/extras")" -eq 1 ]
    [ "$(git config alias.lg | cut -c1-3)" = "log" ]
}

@test "aliases install: never overwrites your edited copy" {
    sed -i.orig 's/^    b = /    br = /' "$(ALIAS_DIR)/commands"
    run git workflow aliases install
    [ "$status" -eq 0 ]
    grep -q '^    br = workflow branch' "$(ALIAS_DIR)/commands"
    run git br
    [ "$status" -eq 0 ]
}

@test "aliases install: an alias you already have keeps working" {
    git workflow aliases remove >/dev/null 2>&1
    rm -rf "$(ALIAS_DIR)"
    git config --global alias.c '!echo mine'

    run git workflow aliases install
    [ "$status" -eq 0 ]
    [[ "$output" == *"Left out 'c'"* ]]
    grep -q '^    # c = workflow commit' "$(ALIAS_DIR)/commands"
    run git c
    [ "$output" = "mine" ]
    run git b
    [ "$status" -eq 0 ]
}

@test "aliases install: warns when a git-<name> program on PATH would run instead" {
    mkdir -p "$BATS_TEST_TMPDIR/old"
    printf '#!/bin/sh\n' >"$BATS_TEST_TMPDIR/old/git-sq"
    chmod +x "$BATS_TEST_TMPDIR/old/git-sq"

    PATH="$BATS_TEST_TMPDIR/old:$PATH" run git workflow aliases install
    [ "$status" -eq 0 ]
    [[ "$output" == *"git-sq runs instead of the alias 'sq'"* ]]
}

@test "aliases install: drops the include of a 1.x alias file" {
    git config --global --add include.path /usr/local/share/git-workflow/git-workflow-aliases
    run git workflow aliases install
    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed the 1.x include"* ]]
    [ "$(include_count /usr/local/share/git-workflow/git-workflow-aliases)" -eq 0 ]
}

@test "aliases remove: stops including the sets and keeps your copies" {
    run git workflow aliases remove
    [ "$status" -eq 0 ]
    [ "$(include_count "$(ALIAS_DIR)/commands")" -eq 0 ]
    [ -f "$(ALIAS_DIR)/commands" ]
    run git b
    [ "$status" -ne 0 ]
}

@test "aliases reset: restores the default and keeps yours as .bak" {
    echo "    mine = status" >>"$(ALIAS_DIR)/extras"
    run git workflow aliases reset extras
    [ "$status" -eq 0 ]
    cmp "$REPO_ROOT/share/aliases/extras" "$(ALIAS_DIR)/extras"
    grep -q 'mine = status' "$(ALIAS_DIR)/extras.bak"

    run git workflow aliases reset
    [ "$status" -ne 0 ]
    run git workflow aliases reset nope
    [ "$status" -ne 0 ]
}

@test "aliases list: shows each alias and where the sets are" {
    run git workflow aliases
    [ "$status" -eq 0 ]
    [[ "$output" =~ git\ sq\ +git\ workflow\ squash ]]
    [[ "$output" == *"$(ALIAS_DIR)/commands (included from ~/.gitconfig)"* ]]
}

# --- messages follow your aliases ------------------------------------------------

@test "messages name commands by your alias, or in full without one" {
    git switch -qc feat
    commit_change a c1
    commit_change a c2
    git push -qu origin feat
    git reset -q --soft origin/main
    git commit -qm squashed

    run git ps
    [[ "$output" == *"Publish the rewrite with: git ps force"* ]]

    git workflow aliases remove >/dev/null 2>&1
    run git workflow push
    [[ "$output" == *"Publish the rewrite with: git workflow push force"* ]]

    git config --global alias.up "workflow ps"
    run git workflow push
    [[ "$output" == *"Publish the rewrite with: git up force"* ]]
}
