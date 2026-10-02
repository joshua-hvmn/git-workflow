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

    GIT_SEQUENCE_EDITOR=$(squash_editor) run git sq
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

@test "c: commits on a protected branch get the same guardrail as qc" {
    git config workflow.strict true
    echo x >>a
    git add a
    run git c fix the bug
    [ "$status" -ne 0 ]
    [[ "$output" == *"workflow.strict"* ]]
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]
}

@test "c: a git-commit flag is rejected instead of becoming the message" {
    git switch -qc feat
    echo x >>a
    git add a
    run git c -m "fix the bug"
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown option '-m'"* ]]
    [ "$(git rev-parse HEAD)" = "$(git rev-parse origin/main)" ]
}

@test "c: -- allows a message that starts with a dash" {
    git switch -qc feat
    echo x >>a
    git add a
    git c -- -x flag removed
    [ "$(git log -1 --format=%s)" = "-x flag removed" ]
}

@test "qc: the word 'push' starts the message instead of selecting push mode" {
    git switch -qc feat
    echo x >>a
    git add a
    run git qc push notifications for alerts
    [ "$status" -eq 0 ]
    [ "$(git log -1 --format=%s)" = "push notifications for alerts" ]
    remote_lacks_ref refs/heads/feat
}

@test "ps force: never force-pushes a protected branch, strict or not" {
    run git ps force </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"refusing to force-push"* ]]
}

@test "ps force: won't overwrite commits it only saw through a background fetch" {
    git switch -qc feat
    commit_change a "mine"
    git push -qu origin feat
    remote_commit feat b # someone else pushes
    git fetch -q origin  # an editor's background fetch picks it up
    git commit -q --amend -m "mine, amended"

    run git ps force
    [ "$status" -ne 0 ]
    git fetch -q origin
    [ "$(git log -1 --format=%s origin/feat)" = "upstream change on feat" ]
}

@test "ps: after a squash it says to force-push instead of replaying old commits" {
    git switch -qc feat
    commit_change a c1
    commit_change a c2
    git push -qu origin feat
    git reset -q --soft origin/main
    git commit -qm squashed

    run git ps
    [ "$status" -ne 0 ]
    [[ "$output" == *"git ps force"* ]]
    [ "$(git log -1 --format=%s)" = "squashed" ]
    [ "$(git rev-list --count origin/main..HEAD)" -eq 1 ]

    run git ps force
    [ "$status" -eq 0 ]
    [ "$(git rev-parse origin/feat)" = "$(git rev-parse HEAD)" ]
}

@test "sq: a hotfix squashes against main, not the dev branch" {
    local_next
    remote_commit main b # a commit on main that next doesn't have
    git b start hotfix v1.0.1 >/dev/null 2>&1
    commit_change a c1
    commit_change a c2

    GIT_SEQUENCE_EDITOR=$(squash_editor) run git sq
    [ "$status" -eq 0 ]
    git merge-base --is-ancestor origin/main HEAD
    [ "$(git rev-list --count origin/main..HEAD)" -eq 1 ]
    # the squashed commits were never pushed, so no force-push is needed
    [[ "$output" != *"git ps force"* ]]
}

@test "pre: a VERSION file that doesn't match stops the tag before it's public" {
    git config workflow.strict true
    local_next
    git b start release v1.1.0 >/dev/null 2>&1
    echo v1.0.0 >VERSION
    git add VERSION
    git commit -qm "forgot to bump"

    run git b pre <<<"y"
    [ "$status" -ne 0 ]
    [[ "$output" == *"VERSION says 'v1.0.0', but this release is v1.1.0"* ]]
    [ -z "$(git tag -l 'v1.1.0-*')" ]

    echo 1.1.0 >VERSION # without the v also counts
    git commit -qam bump
    run git b pre <<<$'y\ny'
    [ "$status" -eq 0 ]
    remote_has_ref refs/tags/v1.1.0-rc.1
}

@test "finish: a VERSION file that doesn't match stops before merging" {
    git config workflow.strict true
    local_next
    git b start release v1.1.0 >/dev/null 2>&1
    echo v1.0.0 >VERSION
    git add VERSION
    git commit -qm "forgot to bump"

    run git b finish <<<"y"
    [ "$status" -ne 0 ]
    [[ "$output" == *"VERSION says"* ]]
    [ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ]
    [ -z "$(git tag -l v1.1.0)" ]

    git config workflow.versionFile ""
    run git b finish <<<$'y\ny'
    [ "$status" -eq 0 ]
}

@test "delete: refuses a branch with unmerged commits unless -f" {
    local_next
    git b start topic foo >/dev/null 2>&1
    commit_change a "unmerged work"
    git push -q origin foo
    git switch -q next

    run git b delete foo -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"git b delete foo -f"* ]]
    git rev-parse --verify --quiet refs/heads/foo >/dev/null

    run git b delete foo -y -f
    [ "$status" -eq 0 ]
    no_local_branch foo
    remote_lacks_ref refs/heads/foo
}

@test "delete: refuses when the remote copy has commits you never fetched" {
    local_next
    git b start topic foo >/dev/null 2>&1
    git switch -q next
    remote_commit foo b # someone else pushed to foo

    run git b delete foo -y
    [ "$status" -ne 0 ]
    [[ "$output" == *"'origin/foo' has commits"* ]]
    remote_has_ref refs/heads/foo
}

@test "delete: -y without a branch name still asks, and -y alone is not a branch" {
    local_next
    git b start topic foo >/dev/null 2>&1

    run git b delete -y </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"Deletion aborted"* ]]
    [ "$(git branch --show-current)" = "foo" ]
}

@test "delete: deletes a branch that only exists on the remote" {
    (cd "$SEED" && git push -q origin main:gone)
    run git b delete gone -y
    [ "$status" -eq 0 ]
    remote_lacks_ref refs/heads/gone
}

@test "start: untracked files don't block starting a branch" {
    local_next
    echo scratch >notes.txt
    run git b start topic foo
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "foo" ]
    [ -f notes.txt ]
}

@test "start: refuses a name that already exists on the remote" {
    local_next
    (cd "$SEED" && git push -q origin main:foo)
    run git b start topic foo
    [ "$status" -ne 0 ]
    [[ "$output" == *"already exists on 'origin'"* ]]
    no_local_branch foo
}

# --- v1.4.2 ------------------------------------------------------------------

@test "finish topic: after a squash it stops instead of merging the old commits" {
    local_next
    git b start topic foo >/dev/null 2>&1
    commit_change a c1
    commit_change a c2
    git push -q origin foo
    GIT_SEQUENCE_EDITOR=$(squash_editor) git sq >/dev/null 2>&1

    run git b finish <<<$'y\ny'
    [ "$status" -ne 0 ]
    [[ "$output" == *"git ps force"* ]]
    [ "$(git rev-parse next)" = "$(git rev-parse origin/next)" ]
    [ "$(git rev-list --count origin/next..foo)" -eq 1 ]
}

@test "qc p: after a squash it refuses to pull the old commits back" {
    git switch -qc feat
    commit_change a c1
    commit_change a c2
    git push -qu origin feat
    GIT_SEQUENCE_EDITOR=$(squash_editor) git sq >/dev/null 2>&1
    echo more >>b
    git add b

    run git qc p more
    [ "$status" -ne 0 ]
    [[ "$output" == *"git ps force"* ]]
    [ "$(git rev-list --count origin/main..HEAD)" -eq 2 ]
    [ "$(git log -1 --format=%s origin/feat)" = "c2" ]
}

@test "sync: after a squash it refuses to pull the old commits back" {
    git switch -qc feat
    commit_change a c1
    commit_change a c2
    git push -qu origin feat
    GIT_SEQUENCE_EDITOR=$(squash_editor) git sq >/dev/null 2>&1

    run git sync
    [ "$status" -ne 0 ]
    [ "$(git rev-list --count origin/main..HEAD)" -eq 1 ]
}

@test "finish topic: merging next in to fix a conflict, then finishing again, works" {
    local_next
    git b start topic foo >/dev/null 2>&1
    commit_change a "work"
    remote_commit next a
    run git b finish <<<"y"
    [ "$status" -ne 0 ]

    # what finish tells you to do: merge the dev branch in and resolve
    git merge origin/next >/dev/null 2>&1 || true
    printf 'a\nresolved\n' >a
    git add a
    git commit -q --no-edit

    run git b finish <<<$'y\ny'
    [ "$status" -eq 0 ]
    no_rebase_in_progress
    git fetch -q --prune origin
    [ "$(git log -1 --format=%s origin/next)" = "Merge branch 'foo' into next" ]
    remote_lacks_ref refs/heads/foo
}

@test "finish release: merging main in to fix a conflict, then finishing again, works" {
    local_next
    git b start release v1.1.0 >/dev/null 2>&1
    commit_change a "release fix"
    remote_commit main a
    run git b finish <<<"y"
    [ "$status" -ne 0 ]

    git merge origin/main >/dev/null 2>&1 || true
    printf 'a\nresolved\n' >a
    git add a
    git commit -q --no-edit

    run git b finish <<<$'y\ny'
    [ "$status" -eq 0 ]
    no_rebase_in_progress
    git fetch -q origin
    [ "$(git rev-parse 'v1.1.0^{commit}')" = "$(git rev-parse origin/main)" ]
}

@test "start: an invalid name fails before switching branches" {
    git switch -qc feat
    run git b start topic "bad..name"
    [ "$status" -ne 0 ]
    [[ "$output" == *"not a valid branch name"* ]]
    [ "$(git branch --show-current)" = "feat" ]
}

@test "strict: a release prefix without a trailing slash still sees the open release" {
    git config workflow.strict true
    git config workflow.releasePrefix release-
    local_next
    git b start release v1.1.0 >/dev/null 2>&1
    git switch -q next

    run git b start release v1.2.0 </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"one release branch at a time"* ]]
    no_local_branch release-v1.2.0
}
