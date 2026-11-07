# fish completion for `git workflow`, and for the aliases that run it
# (`git b`, ...).
#
# Installed as a vendor_conf.d snippet, which fish runs at startup, rather
# than as completions/git-workflow.fish: fish's git completion hands
# `git <alias> ...` to a git-<command>'s completions without the alias's own
# words (`git b start` would arrive as `git-workflow start`). So these are
# completions for `git` itself, which see the whole command line, and
# git-workflow's own completions are none, which keeps that handoff quiet.
#
# From a checkout: source it from ~/.config/fish/config.fish.

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman

# The words for git-workflow typed before the cursor, one per line, with an
# alias's own words in place of its name; fails when the command isn't
# git workflow or an alias for it
function __git_workflow_args
    set -l tokens (commandline -opc)
    set -e tokens[1] # git
    # git's own options, some with a value
    while set -q tokens[1]
        switch $tokens[1]
            case -C -c --git-dir --work-tree --namespace
                set -e tokens[1..2]
            case '-*'
                set -e tokens[1]
            case '*'
                break
        end
    end
    set -q tokens[1]; or return 1
    set -l word $tokens[1]
    set -e tokens[1]
    set -l words
    if test "$word" = workflow
        set words $tokens
    else
        set -l expansion (git config --get "alias.$word" 2>/dev/null | string split -n ' ')
        test "$expansion[1]" = workflow; or return 1
        set words $expansion[2..-1] $tokens
    end
    for w in $words
        echo $w
    end
    return 0
end

function __git_workflow_using
    __git_workflow_args >/dev/null
end

function __git_workflow_branches
    git for-each-ref --format='%(refname:short)' refs/heads 2>/dev/null
    if test "$argv[1]" = remote
        git for-each-ref --format='%(refname:lstrip=3)' refs/remotes 2>/dev/null | string match -v HEAD
    end
end

# The candidates for the word at the cursor, "word<TAB>description"
function __git_workflow_complete
    set -l args (__git_workflow_args)
    set -l n (count $args)
    set -l option 0
    string match -q -- '-*' (commandline -ct); and set option 1

    if test $n -eq 0
        printf '%s\t%s\n' \
            branch 'start, finish, prerelease and release branches' \
            commit 'commit with the message as plain words' \
            quick-commit 'commit, sync with the remote branch, optionally push' \
            push 'sync with the remote branch, then push' \
            sync 'fetch everything, then bring a branch up to date' \
            pull 'switch to a branch and bring it up to date' \
            squash "squash the current branch's own commits" \
            aliases 'set up, list or remove your aliases' \
            help "a command's manual page" \
            version 'the installed version'
        return
    end

    set -l cmd $args[1]
    switch $cmd
        case b
            set cmd branch
        case c
            set cmd commit
        case qc
            set cmd quick-commit
        case ps
            set cmd push
        case sq
            set cmd squash
        case rb-pull
            set cmd pull
    end

    switch $cmd
        case branch
            if test $n -eq 1
                test $option -eq 1; and return
                printf '%s\t%s\n' \
                    start "start a branch of one of the flow's types" \
                    pre 'tag the branch as a prerelease and push it' \
                    prerelease 'tag the branch as a prerelease and push it' \
                    release "tag the newest prerelease's commit as the release" \
                    finish 'integrate per the flow: merge, or open a pull request' \
                    delete 'delete a branch locally and on the remote' \
                    status "where you are in the flow and what's next" \
                    config 'the flow and its settings' \
                    help usage \
                    version 'the installed version'
                return
            end
            switch $args[2]
                case start
                    if test $option -eq 1
                        echo --yes
                    else if test $n -eq 2
                        git workflow branch config --types 2>/dev/null
                    else if test $n -eq 3
                        if contains -- $args[3] (git workflow branch config --versioned-types 2>/dev/null)
                            printf '%s\tthe next %s version\n' major major minor minor patch patch
                        end
                    end
                case finish
                    if test $option -eq 1
                        echo --yes
                    else if test $n -eq 2
                        __git_workflow_branches
                    end
                case delete
                    if test $option -eq 1
                        printf '%s\t%s\n' -y "don't ask" -f 'even with unmerged commits'
                    else
                        __git_workflow_branches
                    end
                case pre prerelease
                    test $option -eq 1; and printf '%s\n' --dry-run --list --yes
                case release
                    test $option -eq 1; and printf '%s\n' --dry-run --yes
                case status
                    test $option -eq 1; and echo --no-fetch
            end
        case commit
            test $n -eq 1 -a $option -eq 1; and echo --amend
        case quick-commit
            test $n -eq 1 -a $option -eq 1; and echo --push
        case push
            test $n -eq 1; and echo force
        case pull sync squash
            test $n -eq 1; and __git_workflow_branches remote | sort -u
        case aliases
            if test $n -eq 1
                printf '%s\n' list install reset remove help
            else if contains -- $args[2] install reset remove
                printf '%s\n' commands extras
            end
        case help
            test $n -eq 1; and printf '%s\n' branch commit quick-commit push sync pull squash aliases
    end
end

complete -c git -f -n __git_workflow_using -a '(__git_workflow_complete)'
# git-workflow's own completions: none, and no file names (see the top)
complete -c git-workflow -f
