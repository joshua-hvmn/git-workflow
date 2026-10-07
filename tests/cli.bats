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

@test "aliases install: copies commands by default, extras on request, each included once" {
    [ -f "$(ALIAS_DIR)/commands" ]
    [ ! -e "$(ALIAS_DIR)/extras" ]
    cmp "$REPO_ROOT/share/aliases/commands" "$(ALIAS_DIR)/commands"
    [ -z "$(git config alias.lg)" ]

    run git workflow aliases install extras
    [ "$status" -eq 0 ]
    run git workflow aliases install commands extras
    [ "$status" -eq 0 ]
    [ "$(include_count "$(ALIAS_DIR)/commands")" -eq 1 ]
    [ "$(include_count "$(ALIAS_DIR)/extras")" -eq 1 ]
    [ "$(git config alias.lg | cut -c1-3)" = "log" ]
}

@test "aliases install: a copy under your home is included as ~/..." {
    git workflow aliases remove >/dev/null 2>&1
    unset XDG_CONFIG_HOME
    run git workflow aliases install
    [ "$status" -eq 0 ]
    [ "$(include_count "~/.config/git-workflow/aliases/commands")" -eq 1 ]
    run git b
    [ "$status" -eq 0 ]

    # still found either way, so a second install adds nothing
    run git workflow aliases install
    [ "$(include_count "~/.config/git-workflow/aliases/commands")" -eq 1 ]
    run git workflow aliases
    [[ "$output" == *"$HOME/.config/git-workflow/aliases/commands (included from ~/.gitconfig)"* ]]

    # the set's own aliases aren't "yours", so reset doesn't comment them out
    run git workflow aliases reset commands
    [ "$status" -eq 0 ]
    cmp "$REPO_ROOT/share/aliases/commands" "$HOME/.config/git-workflow/aliases/commands"

    run git workflow aliases remove
    [ "$status" -eq 0 ]
    [ "$(include_count "~/.config/git-workflow/aliases/commands")" -eq 0 ]
}

@test "aliases remove: also finds an include written with the full path" {
    git workflow aliases remove >/dev/null 2>&1
    unset XDG_CONFIG_HOME
    git workflow aliases install >/dev/null 2>&1
    git config --global --unset-all include.path
    git config --global --add include.path "$HOME/.config/git-workflow/aliases/commands"

    run git workflow aliases remove commands
    [ "$status" -eq 0 ]
    [[ "$output" == *"no longer includes"* ]]
    [ -z "$(git config --global --get-all include.path)" ]
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
    # the 1.x file had the extras, so the upgrade keeps them
    [ "$(include_count "$(ALIAS_DIR)/extras")" -eq 1 ]
    [ "$(git config alias.lg | cut -c1-3)" = "log" ]
}

@test "aliases install: with sets named, an upgrade installs just those" {
    git workflow aliases remove >/dev/null 2>&1
    rm -rf "$(ALIAS_DIR)"
    git config --global --add include.path /usr/local/share/git-workflow/git-workflow-aliases
    run git workflow aliases install commands
    [ "$status" -eq 0 ]
    [[ "$output" == *"Removed the 1.x include"* ]]
    [ ! -e "$(ALIAS_DIR)/extras" ]
}

@test "make aliases SETS=extras installs that set" {
    run make -C "$REPO_ROOT" --no-print-directory aliases SETS=extras
    [ "$status" -eq 0 ]
    [ "$(include_count "$(ALIAS_DIR)/extras")" -eq 1 ]
    [ "$(git config alias.lg | cut -c1-3)" = "log" ]
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
    git workflow aliases install extras >/dev/null 2>&1
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

# --- every usage path runs ------------------------------------------------------

@test "branch help and -h print the usage, with or without aliases" {
    run git workflow branch help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage: git b [<subcommand>]"* ]]
    run git b -h
    [ "$status" -eq 0 ]

    git workflow aliases remove >/dev/null 2>&1
    run git workflow branch help
    [ "$status" -eq 0 ]
    [[ "$output" == *"usage: git workflow branch [<subcommand>]"* ]]
}

@test "branch start with no mode prints its usage" {
    run git workflow branch start
    [ "$status" -ne 0 ]
    [[ "$output" == *"usage: git b start <topic|hotfix|release>"* ]]
    [[ "$output" != *"command not found"* ]]
}

@test "without aliases, messages never name a 1.x alias" {
    git workflow aliases remove >/dev/null 2>&1
    git switch -qc feat
    commit_change a c1
    commit_change a c2
    git push -qu origin feat
    git reset -q --soft origin/main
    git commit -qm squashed

    run git workflow sync
    [ "$status" -ne 0 ]
    [[ "$output" == *"git workflow push force"* ]]

    local_next
    git workflow branch start release v1.1.0 >/dev/null 2>&1
    remote_commit release/v1.1.0 a
    run git workflow branch pre </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"Run 'git workflow sync' first"* ]]
}

@test "commands outside a repository fail with git's own message" {
    cd "$BATS_TEST_TMPDIR"
    export GIT_CEILING_DIRECTORIES="$(dirname "$BATS_TEST_TMPDIR")" # in case TMPDIR is in a repo
    run git workflow commit hi
    [ "$status" -eq 128 ]
    [[ "$output" == *"not a git repository"* ]]
    [[ "$output" != *"usage: git diff"* ]]
    run git workflow push
    [ "$status" -eq 128 ]
    [[ "$output" == *"not a git repository"* ]]
    run git workflow version
    [ "$status" -eq 0 ]
}

@test "aliases install: an alias in a file you include keeps working" {
    git workflow aliases remove >/dev/null 2>&1
    rm -rf "$(ALIAS_DIR)"
    printf '[alias]\n    c = !echo mine\n' >"$BATS_TEST_TMPDIR/my aliases"
    git config --global --add include.path "$BATS_TEST_TMPDIR/my aliases"

    run git workflow aliases install
    [ "$status" -eq 0 ]
    [[ "$output" == *"Left out 'c'"* ]]
    run git c
    [ "$output" = "mine" ]
}

# --- make link ------------------------------------------------------------------

@test "make link and unlink clear away 1.x's links into this checkout, and only those" {
    local bin="$BATS_TEST_TMPDIR/linkdir" root
    root=$(cd "$REPO_ROOT" && pwd -P) # make's CURDIR has symlinks resolved
    mkdir -p "$bin"
    ln -s "$root/scripts/git-b" "$bin/git-b" # what 1.x make link left
    ln -s /somewhere/else/git-c "$bin/git-c" # not ours

    run make -C "$REPO_ROOT" --no-print-directory link LINKDIR="$bin"
    [ "$status" -eq 0 ]
    [ ! -L "$bin/git-b" ]
    [ -L "$bin/git-c" ]
    [ "$(readlink "$bin/git-workflow")" = "$root/bin/git-workflow" ]

    ln -s "$root/scripts/git-sq" "$bin/git-sq"
    run make -C "$REPO_ROOT" --no-print-directory unlink LINKDIR="$bin"
    [ "$status" -eq 0 ]
    [ ! -L "$bin/git-sq" ]
    [ ! -L "$bin/git-workflow" ]
    [ -L "$bin/git-c" ]
}
