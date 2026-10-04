# shellcheck shell=bash
# git workflow aliases: set up, list, reset or remove the git aliases
# bin/git-workflow sources this file with the command's arguments in "$@".

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.
#
# Each alias set is a git config file. The defaults ship in share/aliases/;
# `install` copies a set into ~/.config/git-workflow/aliases/ and includes that
# copy from ~/.gitconfig. The copy is yours to edit: install never overwrites
# it, and `reset` brings the default back (keeping yours as <set>.bak).

# shellcheck disable=SC2088 # "~/.gitconfig" in messages is text, not a path
. "$GIT_WORKFLOW_DATADIR/core.sh"

ALIAS_SETS="commands extras"
DEFAULTS_DIR="$GIT_WORKFLOW_DATADIR/aliases"
USER_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/git-workflow/aliases"

aliases_usage() {
    cat >&2 <<EOF
usage: git workflow aliases [list]
       git workflow aliases install [<set>...]
       git workflow aliases reset <set>...
       git workflow aliases remove [<set>...]

Sets: commands  b = workflow branch, c = workflow commit, ... (the 1.x names)
      extras    lg, graph, s, st, aa, au, fprune

install  copy each set (default: both) to $USER_DIR/<set>
         unless it's already there, and include it from ~/.gitconfig
reset    replace your copy with the default, keeping yours as <set>.bak
remove   stop including the set; your copy stays
list     show the aliases that run git-workflow commands, and each set's state
EOF
}

# The sets named on the command line, or all of them, one per line
pick_sets() {
    local s
    # shellcheck disable=SC2086 # split the list
    [ "$#" -gt 0 ] || set -- $ALIAS_SETS
    for s in "$@"; do
        case " $ALIAS_SETS " in
        *" $s "*) printf '%s\n' "$s" ;;
        *)
            err "there is no alias set '$s'. The sets are: $ALIAS_SETS"
            return 1
            ;;
        esac
    done
}

included() {
    git config --global --get-all include.path 2>/dev/null | grep -qxF "$1"
}

# Aliases you defined yourself. --global without --includes reads only
# ~/.gitconfig (and ~/.config/git/config), not the files they include.
own_aliases() {
    local key _
    git config --global --get-regexp '^alias\.' 2>/dev/null |
        while read -r key _; do printf '%s\n' "${key#alias.}"; done
}

# The alias names an alias file sets (lines that are commented out don't count)
names_in() {
    awk '/^[ \t]*[A-Za-z0-9-]+[ \t]*=/ {
        name = $0; sub(/^[ \t]*/, "", name); sub(/[ \t]*=.*/, "", name)
        print tolower(name)
    }' "$1"
}

# copy_default <set> <dest>: copy a default set, commenting out any alias you
# already have, so that yours keeps working (an include later in ~/.gitconfig
# would otherwise win)
copy_default() {
    local set="$1" dest="$2" taken name
    taken=" $(own_aliases | tr '\n' ' ')"
    mkdir -p "$(dirname "$dest")"
    TAKEN="$taken" awk '/^[ \t]*[A-Za-z0-9-]+[ \t]*=/ {
        name = $0; sub(/^[ \t]*/, "", name); sub(/[ \t]*=.*/, "", name)
        if (index(ENVIRON["TAKEN"], " " tolower(name) " ")) {
            line = $0; sub(/^[ \t]*/, "", line)
            print "    # " line "    # off: you already have alias." tolower(name)
            next
        }
    }
    { print }' "$DEFAULTS_DIR/$set" >"$dest.tmp"
    mv "$dest.tmp" "$dest"
    for name in $(names_in "$DEFAULTS_DIR/$set"); do
        case "$taken" in
        *" $name "*) note "Left out '$name': you already have alias.$name. Edit $dest to change that." ;;
        esac
    done
}

# Git runs a git-<name> program on PATH before it looks at aliases
warn_shadowed() {
    local name path
    for name in $(names_in "$1"); do
        path=$(command -v "git-$name" 2>/dev/null) || continue
        warn "$path runs instead of the alias '$name', because git prefers programs on PATH." \
            "Delete it if git-workflow 1.x left it there, or rename the alias in $1."
    done
}

# 1.x had you include its alias file straight from the install or a checkout
drop_1x_includes() {
    local path
    git config --global --get-all include.path 2>/dev/null | while IFS= read -r path; do
        case "$path" in
        */git-workflow/git-workflow-aliases | */alias-core/git-workflow-aliases)
            git config --global --fixed-value --unset-all include.path "$path" &&
                note "Removed the 1.x include of $path"
            ;;
        esac
    done
}

aliases_install() {
    local sets set dest
    sets=$(pick_sets "$@") || return 1
    drop_1x_includes
    for set in $sets; do
        dest="$USER_DIR/$set"
        if [ -e "$dest" ]; then
            info "Using your existing $dest"
        else
            copy_default "$set" "$dest"
            note "Created $dest"
        fi
        if ! included "$dest"; then
            git config --global --add include.path "$dest"
            note "~/.gitconfig now includes $dest"
        fi
        warn_shadowed "$dest"
    done
}

aliases_reset() {
    local sets set dest
    if [ "$#" -eq 0 ]; then
        err "name the set(s) to reset: git workflow aliases reset <commands|extras>..."
        return 1
    fi
    sets=$(pick_sets "$@") || return 1
    for set in $sets; do
        dest="$USER_DIR/$set"
        if [ -e "$dest" ]; then
            cp "$dest" "$dest.bak"
            info "Saved your copy as $dest.bak"
        fi
        copy_default "$set" "$dest"
        note "Restored the default $dest"
    done
}

aliases_remove() {
    local sets set dest removed=""
    sets=$(pick_sets "$@") || return 1
    for set in $sets; do
        dest="$USER_DIR/$set"
        if included "$dest"; then
            git config --global --fixed-value --unset-all include.path "$dest"
            note "~/.gitconfig no longer includes $dest"
            removed=1
        else
            info "~/.gitconfig doesn't include $dest"
        fi
    done
    if [ -n "$removed" ]; then
        info "Your copies stay in $USER_DIR. Delete them if you don't want them back."
    fi
}

aliases_list() {
    local cmd name set dest state any=""
    printf 'Aliases that run git-workflow commands:\n'
    while read -r cmd name; do
        [ -n "$cmd" ] || continue
        printf '  git %-12s git workflow %s\n' "$name" "$cmd"
        any=1
    done <<<"$WF_ALIASES"
    if [ -z "$any" ]; then
        printf '  (none yet: git workflow aliases install)\n'
    fi
    printf '\nAlias sets:\n'
    for set in $ALIAS_SETS; do
        dest="$USER_DIR/$set"
        if [ ! -e "$dest" ]; then
            state="not installed"
        elif included "$dest"; then
            state="included from ~/.gitconfig"
        else
            state="not included"
        fi
        printf '  %-9s %s (%s)\n' "$set" "$dest" "$state"
        if [ -e "$dest" ]; then
            warn_shadowed "$dest"
        fi
    done
}

case "${1:-list}" in
list) aliases_list ;;
install)
    shift
    aliases_install "$@"
    ;;
reset)
    shift
    aliases_reset "$@"
    ;;
remove)
    shift
    aliases_remove "$@"
    ;;
help | -h) aliases_usage ;;
*)
    err "unknown subcommand '$1'"
    aliases_usage
    exit 1
    ;;
esac
