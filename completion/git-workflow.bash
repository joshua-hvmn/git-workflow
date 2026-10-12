# shellcheck shell=bash
# Bash completion for `git workflow` and the aliases that run it (`git b`, ...).
#
# Nothing to source by hand: git's own completion loads this file (installed as
# .../bash-completion/completions/git-workflow) the first time you complete a
# `git workflow` command, and calls _git_workflow. From a checkout, source it
# from ~/.bashrc after git's completion.

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman

# cur, words and cword are set by git's completion before it calls this
# shellcheck disable=SC2154

__git_workflow_commands="branch commit quick-commit push sync pull squash aliases help version"

_git_workflow() {
    local idx="${__git_cmd_idx:-1}" name word found="" cmd sub n
    local -a expansion args=()

    # Through an alias ("b = workflow branch"), git's completion calls this
    # with the alias's first word put in place of yours, so look up what you
    # typed: whatever the alias has after "workflow" comes first.
    name="${words[idx]}"
    if [ "$name" = workflow ]; then
        name="${COMP_WORDS[idx]:-workflow}"
    fi
    if [ "$name" != workflow ]; then
        read -r -a expansion <<<"$(__git config --get "alias.$name")"
        for word in "${expansion[@]}"; do
            if [ -n "$found" ]; then
                args+=("$word")
            elif [ "$word" = workflow ]; then
                found=1
            fi
        done
    fi
    # Then the words typed after the command, up to the one being completed
    args+=("${words[@]:idx+1:cword-idx-1}")

    n=${#args[@]}
    if [ "$n" -eq 0 ]; then
        __gitcomp "$__git_workflow_commands"
        return
    fi
    cmd="${args[0]}" sub="${args[1]-}"
    case "$cmd" in
    b) cmd=branch ;;
    c) cmd=commit ;;
    qc) cmd=quick-commit ;;
    ps) cmd=push ;;
    sq) cmd=squash ;;
    rb-pull) cmd=pull ;;
    esac

    case "$cmd" in
    branch)
        if [ "$n" -eq 1 ]; then
            case "$cur" in
            -*) _git_branch ;; # options go to git branch
            *) __gitcomp "start pre prerelease finish delete config help version" ;;
            esac
            return
        fi
        case "$sub" in
        start)
            if [ "$n" -eq 2 ]; then
                __gitcomp "topic release hotfix"
            fi
            ;;
        finish)
            if [ "$n" -eq 2 ]; then
                __gitcomp_direct "$(__git_heads "" "$cur" " ")"
            fi
            ;;
        delete)
            case "$cur" in
            -*) __gitcomp "-y -f" ;;
            *) __gitcomp_direct "$(__git_heads "" "$cur" " ")" ;;
            esac
            ;;
        pre | prerelease)
            case "$cur" in
            -*) __gitcomp "--dry-run --list" ;;
            esac
            ;;
        esac
        ;;
    commit)
        if [ "$n" -eq 1 ]; then
            case "$cur" in
            -*) __gitcomp "--amend" ;;
            esac
        fi
        ;;
    quick-commit)
        if [ "$n" -eq 1 ]; then
            case "$cur" in
            -*) __gitcomp "--push" ;;
            esac
        fi
        ;;
    push)
        if [ "$n" -eq 1 ]; then
            __gitcomp "force"
        fi
        ;;
    pull | sync)
        if [ "$n" -eq 1 ]; then
            __gitcomp_direct "$(__git_heads "" "$cur" " ")"
        fi
        ;;
    squash)
        if [ "$n" -eq 1 ]; then
            __git_complete_refs
        fi
        ;;
    aliases)
        if [ "$n" -eq 1 ]; then
            __gitcomp "list install reset remove help"
        else
            case "$sub" in
            install | reset | remove) __gitcomp "commands extras" ;;
            esac
        fi
        ;;
    help)
        if [ "$n" -eq 1 ]; then
            __gitcomp "branch commit quick-commit push sync pull squash aliases"
        fi
        ;;
    esac
}
