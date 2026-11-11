#!/usr/bin/env bats
# GitLab flow: main, then environment branches, promote, and hotfixes that
# start from production and are merged back up the chain.

load test_helper

# A GitLab flow repository, with staging and production on the remote at
# main's first commit
gitlab_flow() {
    git config workflow.flow gitlab
    git push -q origin main:staging main:production
    git fetch -q origin
}

# The commit a branch points at on the remote
remote_sha() {
    git ls-remote "$REMOTE_DIR" "refs/heads/$1" | cut -f1
}

# The same tree: same content, whatever the commits
same_tree() {
    [ "$(git rev-parse "$1^{tree}")" = "$(git rev-parse "$2^{tree}")" ]
}

# Someone else merged a change into main
main_moves_on() {
    remote_commit main "${1:-b}"
    git fetch -q origin
}

@test "gitlab flow: config shows the chain, the types, and protects the environments" {
    gitlab_flow
    run git b config
    [ "$status" -eq 0 ]
    [[ "$output" == *"flow             gitlab  (git config)"* ]]
    [[ "$output" == *"environments     staging production  (flow gitlab)"* ]]
    [[ "$output" == *"protected        main staging production"* ]]
    [[ "$output" == *"topic     (no prefix) from main into main by merge"* ]]
    [[ "$output" == *"hotfix    hotfix/     from production into production by merge, merged back into staging and main"* ]]

    run git b config --environments
    [ "$output" = $'staging\nproduction' ]
}

@test "promote: creates a missing environment from the one before it" {
    git config workflow.flow gitlab
    run git b promote -y </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"'staging' isn't on 'origin' yet. Create it at main's"* ]]
    [ "$(remote_sha staging)" = "$(remote_sha main)" ]
    remote_lacks_ref refs/heads/production

    run git b promote -y </dev/null
    [ "$status" -eq 0 ]
    [ "$(remote_sha production)" = "$(remote_sha main)" ]

    run git b promote
    [ "$status" -eq 0 ]
    [[ "$output" == *"Every environment is up to date: main -> staging -> production."* ]]
}

@test "promote: fast-forwards staging to main, then production to staging, one at a time" {
    gitlab_flow
    main_moves_on
    main_moves_on

    run git b promote -y </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"Promote 2 commits from 'main' to 'staging' (fast-forward staging to"* ]]
    [ "$(remote_sha staging)" = "$(remote_sha main)" ]
    [ "$(remote_sha production)" != "$(remote_sha main)" ]

    run git b promote -y </dev/null
    [ "$status" -eq 0 ]
    [ "$(remote_sha production)" = "$(remote_sha staging)" ]
}

@test "promote -n: shows what would move, and changes nothing" {
    gitlab_flow
    main_moves_on
    before=$(remote_sha staging)

    run git b promote staging -n
    [ "$status" -eq 0 ]
    [[ "$output" == *"Would move 'staging' to main's"*"promoting 1 commit:"* ]]
    [[ "$output" == *"upstream change on main"* ]]
    [ "$(remote_sha staging)" = "$before" ]
}

@test "promote: a named environment that's up to date says so; an unknown one is an error" {
    gitlab_flow
    run git b promote production
    [ "$status" -eq 0 ]
    [[ "$output" == *"'production' is up to date with 'staging'"* ]]

    run git b promote prod
    [ "$status" -ne 0 ]
    [[ "$output" == *"'prod' isn't an environment branch. The environments: staging production."* ]]
}

@test "promote: refuses an environment with changes the one before it doesn't have" {
    gitlab_flow
    remote_commit production a # a fix made straight on production, never merged back
    main_moves_on
    git b promote staging -y </dev/null >/dev/null 2>&1
    before=$(remote_sha production)

    run git b promote production -y </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"'production' has changes 'staging' doesn't"* ]]
    [[ "$output" == *"upstream change on production"* ]]
    [ "$(remote_sha production)" = "$before" ]

    run git b status
    [[ "$output" == *"production   has changes staging doesn't: merge production into staging"* ]]
}

@test "promote: after a squash-merged promotion, production still counts as promoted, and the next one keeps the tree" {
    gitlab_flow
    main_moves_on
    git b promote staging -y </dev/null >/dev/null 2>&1
    # The forge squash-merged a promotion pull request into production
    (cd "$SEED" && git fetch -q origin && git switch -q -C production origin/production &&
        git merge -q --squash origin/staging >/dev/null && git commit -qm "Promote staging to production (!3)" &&
        git push -q origin production)
    git fetch -q origin
    same_tree origin/production origin/staging

    run git b status
    [[ "$output" == *"production   up to date with staging"* ]]

    main_moves_on a
    git b promote staging -y </dev/null >/dev/null 2>&1
    run git b promote production -y </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"with exactly staging's tree"* ]]
    git fetch -q origin
    same_tree origin/production origin/staging
    git merge-base --is-ancestor origin/staging origin/production
}

@test "hotfix: starts from production, merges into it and back into staging and main, in one push" {
    gitlab_flow
    main_moves_on # main has work production doesn't
    git b promote staging -y </dev/null >/dev/null 2>&1

    run git b start hotfix fix-login
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = hotfix/fix-login ]
    [ "$(git rev-parse HEAD)" = "$(remote_sha production)" ]
    commit_change a "fix the login"

    run git b finish -y </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"Merge 'hotfix/fix-login' into production, then production into staging and main, and push? [y/N]: y (-y)"* ]]
    git fetch -q --prune origin
    for b in production staging main; do
        git log --format=%s "origin/$b" | grep -qx "fix the login"
    done
    remote_lacks_ref refs/heads/hotfix/fix-login

    # Merged back, so production is part of staging, and promoting is a fast-forward
    git merge-base --is-ancestor origin/production origin/staging
    run git b promote production -y </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"fast-forward production"* ]]
}

@test "hotfix, with pull requests: into production, then back-merge pull requests into staging and main" {
    gitlab_flow
    fake_gh
    main_moves_on
    git b start hotfix fix-login >/dev/null 2>&1
    commit_change a "fix the login"

    run git b finish <<<"y"
    [ "$status" -eq 0 ]
    [ "$(cat "$GH_LOG")" = "pr create --base production --head hotfix/fix-login --fill" ]

    merge_pr hotfix/fix-login production
    : >"$GH_LOG"
    run git b status
    [[ "$output" == *"Merged into origin/production."* ]]

    run git b finish hotfix/fix-login <<<$'y\ny\ny'
    [ "$status" -eq 0 ]
    [ "$(sed -n 1p "$GH_LOG")" = "pr create --base staging --head production --title Merge production into staging --body Back-merge. Merge it with a merge commit, so staging has what production has." ]
    [ "$(sed -n 2p "$GH_LOG")" = "pr create --base main --head production --title Merge production into main --body Back-merge. Merge it with a merge commit, so main has what production has." ]
    # The hotfix is on production, so it counts as merged, and is deleted
    no_local_branch hotfix/fix-login
    remote_lacks_ref refs/heads/hotfix/fix-login
}

@test "status: a hotfix merged into production but not back is left to do" {
    gitlab_flow
    git b start hotfix fix-login >/dev/null 2>&1
    commit_change a "fix the login"
    git push -q origin hotfix/fix-login
    (cd "$SEED" && git fetch -q origin && git switch -q -C production origin/production &&
        git merge -q --no-ff --no-edit origin/hotfix/fix-login && git push -q origin production)
    git switch -q main

    run git b status
    [[ "$output" == *"gitlab flow: main -> staging -> production; latest release v1.0.0."* ]]
    [[ "$output" == *"hotfix/fix-login is merged into origin/production, but not back into staging and main: git b finish hotfix/fix-login"* ]]
}

@test "promote, with pull requests: opens one from the environment before, or shows the open one" {
    gitlab_flow
    fake_gh
    main_moves_on

    run git b promote <<<"y"
    [ "$status" -eq 0 ]
    [[ "$(cat "$GH_LOG")" == "pr create --base staging --head main --title Promote main to staging --body Moves staging to what main has, up to "* ]]
    [ "$(remote_sha staging)" != "$(remote_sha main)" ]

    : >"$GH_LOG"
    gh_view "OPEN https://github.com/o/r/pull/9"
    run git b promote staging
    [ "$status" -eq 0 ]
    [[ "$output" == *"already open: https://github.com/o/r/pull/9"* ]]
    [ ! -s "$GH_LOG" ]
}

@test "status: the environments, each against the one before it" {
    gitlab_flow
    main_moves_on
    main_moves_on
    git switch -q main
    git sync >/dev/null 2>&1

    run git b status
    [ "$status" -eq 0 ]
    [[ "$output" == *$'Environments (main -> staging -> production):\n  staging      2 commits behind main: git b promote staging\n  production   up to date with staging'* ]]

    git switch -q staging
    run git b status
    [[ "$output" == *"On staging, an environment branch: 2 commits behind main: git b promote staging."* ]]
}

@test "environments: renamed in a repository's .gitworkflow, and hotfixes follow the last one" {
    printf '[workflow]\n    flow = gitlab\n    environments = pre-production live\n' >.gitworkflow
    git push -q origin main:pre-production main:live
    git fetch -q origin

    run git b config
    [[ "$output" == *"hotfix    hotfix/     from live into live by merge, merged back into pre-production and main"* ]]
    run git b start hotfix quick
    [ "$status" -eq 0 ]
    [ "$(git rev-parse HEAD)" = "$(remote_sha live)" ]
}

@test "environments: a keyword, the main branch, a duplicate or a bad name is reported and left out" {
    git config workflow.flow gitlab
    git config workflow.environments "main staging staging bad..name *"
    run git b config
    [[ "$output" == *"'main' can't be an environment"* ]]
    [[ "$output" == *"'staging' can't be an environment"* ]]
    [[ "$output" == *"'bad..name' is not a valid branch name"* ]]
    [[ "$output" == *"'*' is not a valid branch name"* ]]
    [[ "$output" == *"environments     staging  (git config)"* ]]
}

@test "environments: protected, so committing on one warns, and a flow without them can't promote" {
    gitlab_flow
    git switch -q staging
    echo x >>a
    git add a
    run git c fix on staging </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"'staging' is a protected branch"* ]]

    git switch -q -f main
    git config workflow.flow github
    run git b promote
    [ "$status" -ne 0 ]
    [[ "$output" == *"the github flow has no environment branches to promote"* ]]
}

@test "start: a missing environment to start from says how to create it" {
    git config workflow.flow gitlab
    run git b start hotfix fix
    [ "$status" -ne 0 ]
    [[ "$output" == *"could not find branch 'production'"* ]]
    [[ "$output" == *"Create it from staging with: git b promote production"* ]]
}
