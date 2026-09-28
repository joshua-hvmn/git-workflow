#!/usr/bin/env bats
# One test per fixed bug, grouped by the release that fixed it.
# Each one fails against the release before it.

load test_helper

# --- v1.3.0 ------------------------------------------------------------------

@test "qc: partially staged changes stay partial (commit before sync)" {
    git switch -qc feat
    git push -qu origin feat
    echo x >>a
    echo y >>b
    git add a

    run git qc "only a" <<<"y"
    [ "$status" -eq 0 ]

    run git show --name-only --format= HEAD
    [ "$output" = "a" ]
    run git status --short
    [ "$output" = " M b" ]
}

@test "finish: rejected push offers a rollback, then finish can simply rerun" {
    local_next
    git b start hotfix v1.0.1 >/dev/null 2>&1
    commit_change b "hot"
    reject_pushes

    run git b finish <<<$'y\ny'
    [ "$status" -ne 0 ]
    [[ "$output" == *"git push --atomic origin main next refs/tags/v1.0.1"* ]]
    [[ "$output" == *"Rolled back"* ]]
    [ "$(git branch --show-current)" = "hotfix/v1.0.1" ]
    [ -z "$(git tag -l v1.0.1)" ]
    [ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ]
    [ "$(git rev-parse next)" = "$(git rev-parse origin/next)" ]

    allow_pushes
    run git b finish <<<$'y\ny'
    [ "$status" -eq 0 ]
    remote_has_ref refs/tags/v1.0.1
}

@test "finish: declining the rollback keeps local state and prints the retry command" {
    local_next
    git b start hotfix v1.0.1 >/dev/null 2>&1
    commit_change b "hot"
    reject_pushes

    run git b finish <<<$'y\nn'
    [ "$status" -ne 0 ]
    [[ "$output" == *"git push --atomic origin main next refs/tags/v1.0.1"* ]]
    [ -n "$(git tag -l v1.0.1)" ]

    allow_pushes
    git push -q --atomic origin main next refs/tags/v1.0.1
    remote_has_ref refs/tags/v1.0.1
}

@test "start: works on a fresh clone with no local dev branch" {
    run git b start topic foo
    [ "$status" -eq 0 ]
    [[ "$output" == *"Created local 'next' tracking 'origin/next'"* ]]
    [ "$(git branch --show-current)" = "foo" ]
    [ "$(git rev-parse --abbrev-ref next@{upstream})" = "origin/next" ]
}

@test "finish: refuses to run with uncommitted tracked changes" {
    local_next
    git b start topic foo >/dev/null 2>&1
    commit_change a "work"
    echo dirty >>b

    run git b finish <<<"y"
    [ "$status" -ne 0 ]
    [[ "$output" == *"uncommitted changes"* ]]
    [ "$(git branch --show-current)" = "foo" ]
}

@test "delete: refuses to switch away from the current branch with uncommitted changes" {
    local_next
    git b start topic foo >/dev/null 2>&1
    echo dirty >>b

    run git b delete <<<"y"
    [ "$status" -ne 0 ]
    [ "$(git branch --show-current)" = "foo" ]
}

@test "c: every word becomes the commit message" {
    git switch -qc feat
    echo z >>a
    git add a
    git c fix the bug
    [ "$(git log -1 --format=%s)" = "fix the bug" ]
}

@test "ps: pushes to workflow.remote, not a hardcoded origin" {
    git remote rename origin upstream
    git config workflow.remote upstream
    git switch -qc feat
    commit_change a "q"

    run git ps
    [ "$status" -eq 0 ]
    [ "$(git rev-parse --abbrev-ref feat@{upstream})" = "upstream/feat" ]
}

@test "qc p: pushes to workflow.remote" {
    git remote rename origin upstream
    git config workflow.remote upstream
    git switch -qc feat
    echo q >>a
    git add a

    run git qc p "msg"
    [ "$status" -eq 0 ]
    remote_has_ref refs/heads/feat
}

@test "TEST_MODE in the environment no longer mocks git" {
    git switch -qc feat
    echo z >>a
    git add a
    TEST_MODE=1 git c real commit
    [ "$(git log -1 --format=%s)" = "real commit" ]
}

@test "start: a branch can be named 'null'" {
    local_next
    run git b start topic null
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "null" ]
}

@test "pre -n: dry run warns but never aborts, even in strict mode" {
    git config workflow.strict true
    git switch -qc feat
    run git b pre -n v1.1.0-rc.1 </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"Would tag"* ]]
    [[ "$output" != *"aborting"* ]]
}

@test "pre -l: lists without flow checks" {
    git config workflow.strict true
    git switch -qc feat
    run git b pre -l </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"cannot list prereleases"* ]]
    [[ "$output" != *"aborting"* ]]
}

@test "c --amend with no message keeps the previous message" {
    git switch -qc feat
    commit_change a "keep this message"
    echo more >>a
    git add a

    git c --amend </dev/null
    [ "$(git log -1 --format=%s)" = "keep this message" ]
    [ "$(git rev-list --count origin/main..HEAD)" -eq 1 ]
}

@test "sq: squashes in place instead of rebasing onto a newer dev branch" {
    local_next
    git b start topic foo >/dev/null 2>&1
    commit_change a c1
    commit_change a c2
    commit_change a c3
    base=$(git merge-base HEAD origin/next)
    # next moves on upstream and the local copy is updated too
    remote_commit next b
    git fetch -q origin
    git branch -f next origin/next

    GIT_SEQUENCE_EDITOR="sed -i '2,\$s/^pick/fixup/'" run git sq
    [ "$status" -eq 0 ]
    [ "$(git merge-base HEAD origin/next)" = "$base" ]
    [ "$(git rev-list --count "$base"..HEAD)" -eq 1 ]
}

@test "sq: warns before rewriting a protected branch" {
    git config workflow.strict true
    run git sq </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"protected branch"* ]]
}

@test "ps: refuses a detached HEAD" {
    git switch -q --detach
    run git ps
    [ "$status" -ne 0 ]
    [[ "$output" == *"detached HEAD"* ]]
}

@test "qc p: refuses a detached HEAD before committing" {
    git switch -q --detach
    echo x >>a
    git add a
    run git qc p msg
    [ "$status" -ne 0 ]
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]
}

@test "b version: prints the VERSION file" {
    run git b version
    [ "$status" -eq 0 ]
    [ "$output" = "git-workflow $(cat "$REPO_ROOT/VERSION")" ]
}

# --- v1.4.0 ------------------------------------------------------------------

@test "finish topic: a rejected push rolls back, and finish can simply rerun" {
    local_next
    git b start topic foo >/dev/null 2>&1
    commit_change a "work"
    reject_pushes

    run git b finish <<<"y"
    [ "$status" -ne 0 ]
    [[ "$output" == *"Rolled back"* ]]
    [ "$(git branch --show-current)" = "foo" ]
    [ "$(git rev-parse next)" = "$(git rev-parse origin/next)" ]

    allow_pushes
    run git b finish <<<$'y\ny'
    [ "$status" -eq 0 ]
    git fetch -q --prune origin
    [ "$(git log -1 --format=%s origin/next)" = "Merge branch 'foo' into next" ]
}

@test "finish topic: a merge conflict is aborted and rolled back" {
    local_next
    git b start topic foo >/dev/null 2>&1
    commit_change a "work"
    remote_commit next a # conflicting change on next

    run git b finish <<<"y"
    [ "$status" -ne 0 ]
    [[ "$output" == *"conflicted"* ]]
    [ "$(git branch --show-current)" = "foo" ]
    no_merge_in_progress
    [ "$(git rev-parse next)" = "$(git rev-parse origin/next)" ]
}

@test "finish release: a merge conflict with main is aborted and rolled back" {
    local_next
    git b start release v1.1.0 >/dev/null 2>&1
    commit_change a "release fix"
    remote_commit main a # conflicting change on main

    run git b finish <<<"y"
    [ "$status" -ne 0 ]
    [ "$(git branch --show-current)" = "release/v1.1.0" ]
    [ -z "$(git tag -l v1.1.0)" ]
    [ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ]
    no_merge_in_progress
}

@test "finish release: a diverged local next rolls back the merge and tag" {
    local_next
    git b start release v1.1.0 >/dev/null 2>&1
    commit_change a "release fix"
    git switch -q next
    commit_change b "local only"
    git switch -q release/v1.1.0
    remote_commit next b

    run git b finish <<<"y"
    [ "$status" -ne 0 ]
    [[ "$output" == *"diverged"* ]]
    [ "$(git branch --show-current)" = "release/v1.1.0" ]
    [ -z "$(git tag -l v1.1.0)" ]
    [ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ]
    # the unpushed commit on next is untouched
    [ "$(git log -1 --format=%s next)" = "local only" ]
}

@test "finish release: a back-merge conflict can be rolled back" {
    local_next
    git b start release v1.1.0 >/dev/null 2>&1
    commit_change a "release fix"
    remote_commit next a # next changed the same lines after the release branched

    run git b finish <<<$'y\ny'
    [ "$status" -ne 0 ]
    [[ "$output" == *"back-merge"* ]]
    [[ "$output" == *"Rolled back"* ]]
    [ "$(git branch --show-current)" = "release/v1.1.0" ]
    [ -z "$(git tag -l v1.1.0)" ]
    [ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ]
    [ "$(git rev-parse next)" = "$(git rev-parse origin/next)" ]
    no_merge_in_progress
}
