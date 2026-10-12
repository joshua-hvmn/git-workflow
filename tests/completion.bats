#!/usr/bin/env bats
# Bash completion, driven through git's own completion the way bash runs it.

load test_helper

# git's bash completion, wherever this system keeps it
git_completion() {
    local f
    for f in \
        /usr/share/bash-completion/completions/git \
        /usr/local/share/bash-completion/completions/git \
        /opt/homebrew/share/bash-completion/completions/git \
        /opt/homebrew/etc/bash_completion.d/git-completion.bash \
        /usr/local/etc/bash_completion.d/git-completion.bash \
        /usr/share/git-core/contrib/completion/git-completion.bash \
        /Library/Developer/CommandLineTools/usr/share/git-core/git-completion.bash \
        /Applications/Xcode.app/Contents/Developer/usr/share/git-core/git-completion.bash; do
        if [ -r "$f" ]; then
            printf '%s' "$f"
            return 0
        fi
    done
    return 1
}

# The installed copy's completion under make installcheck, the checkout's otherwise
our_completion() {
    if [ -n "${GIT_WORKFLOW_BIN:-}" ]; then
        printf '%s' "$GIT_WORKFLOW_BIN/../share/bash-completion/completions/git-workflow"
    else
        printf '%s' "$REPO_ROOT/completion/git-workflow.bash"
    fi
}

# complete <line>: the words bash would offer for the end of <line>, one per line.
# Call require_git_completion first.
complete() {
    bash --norc --noprofile -c '
        source "$1"
        source "$2"
        read -r -a COMP_WORDS <<<"$3"
        case "$3" in *" ") COMP_WORDS+=("") ;; esac
        COMP_CWORD=$((${#COMP_WORDS[@]} - 1)) COMP_LINE=$3 COMP_POINT=${#3}
        __git_wrap__git_main
        printf "%s\n" "${COMPREPLY[@]}" | sed "s/ *$//"
    ' _ "$GIT_COMPLETION" "$(our_completion)" "$1"
}

# Skips the test unless git's own completion is here and works in this bash
# (ours runs inside it). bats can't skip from inside `run`, hence a step of its own.
require_git_completion() {
    GIT_COMPLETION=$(git_completion) || skip "git's bash completion isn't installed here"
    [[ "$(complete "git chec")" == *checkout* ]] ||
        skip "git's bash completion doesn't work in $(bash -c 'echo "bash $BASH_VERSION"')"
}

@test "completion: commands, then a command's subcommands" {
    require_git_completion
    run complete "git workflow "
    [[ "$output" == *$'branch\n'* ]]
    [[ "$output" == *"quick-commit"* ]]
    run complete "git workflow branch st"
    [ "$output" = "start" ]
    run complete "git workflow branch start "
    [ "$output" = $'topic\nrelease\nhotfix' ]
    run complete "git workflow aliases install e"
    [ "$output" = "extras" ]
}

@test "completion: branch names where a command takes one" {
    require_git_completion
    git branch feat/one
    run complete "git workflow branch finish fe"
    [ "$output" = "feat/one" ]
    run complete "git workflow pull fe"
    [ "$output" = "feat/one" ]
}

@test "completion: through an alias, which already names the command" {
    require_git_completion
    run complete "git b fi"
    [ "$output" = "finish" ]
    run complete "git b start h"
    [ "$output" = "hotfix" ]
    run complete "git ps "
    [ "$output" = "force" ]
    git config --global alias.bb '!git workflow branch'
    run complete "git bb de"
    [ "$output" = "delete" ]
}

@test "completion: options after git b complete as git branch's" {
    require_git_completion
    run complete "git b --show-c"
    [ "$output" = "--show-current" ]
}
