#!/usr/bin/env bats
# End-to-end flows and guardrails.

load test_helper

@test "git flow release: start, two prereleases, finish" {
    local_next
    git b start release v1.1.0 >/dev/null 2>&1
    commit_change a "release fix"

    run git b pre <<<$'y\ny'
    [ "$status" -eq 0 ]
    run git b pre <<<$'y\ny'
    [ "$status" -eq 0 ]
    remote_has_ref refs/tags/v1.1.0-rc.1
    remote_has_ref refs/tags/v1.1.0-rc.2

    run git b pre -l
    [ "$output" = $'v1.1.0-rc.1\nv1.1.0-rc.2' ]

    run git b finish <<<$'y\ny'
    [ "$status" -eq 0 ]
    remote_has_ref refs/tags/v1.1.0
    remote_lacks_ref refs/heads/release/v1.1.0
    git fetch -q origin
    # the tag is on main, and next contains it (back-merge)
    [ "$(git rev-parse 'v1.1.0^{commit}')" = "$(git rev-parse origin/main)" ]
    git merge-base --is-ancestor origin/main origin/next
}

@test "topic: finish merges into next with --no-ff and deletes the branch" {
    local_next
    git b start topic foo >/dev/null 2>&1
    commit_change a "work"

    run git b finish <<<$'y\ny'
    [ "$status" -eq 0 ]
    git fetch -q --prune origin
    [ "$(git log -1 --format=%s origin/next)" = "Merge branch 'foo' into next" ]
    remote_lacks_ref refs/heads/foo
    no_local_branch foo
}

@test "trunk mode: release finish tags main and leaves next alone" {
    git config workflow.devBranch main
    git b start release v1.1.0 >/dev/null 2>&1
    commit_change a "release fix"
    next_before=$(git rev-parse origin/next)

    run git b finish <<<$'y\ny'
    [ "$status" -eq 0 ]
    git fetch -q origin
    [ "$(git rev-parse 'v1.1.0^{commit}')" = "$(git rev-parse origin/main)" ]
    [ "$(git rev-parse origin/next)" = "$next_before" ]
}

@test "hotfix: starts branches from main, not next" {
    local_next
    remote_commit next b # next is ahead of main
    run git b start hotfix v1.0.1
    [ "$status" -eq 0 ]
    [ "$(git merge-base HEAD origin/main)" = "$(git rev-parse origin/main)" ]
    not_ancestor origin/next HEAD
}

@test "hotfix: finish tags main and back-merges it into next" {
    local_next
    remote_commit next b # next has work main doesn't
    git b start hotfix v1.0.1 >/dev/null 2>&1
    commit_change a "hot"

    run git b finish <<<$'y\ny'
    [ "$status" -eq 0 ]
    git fetch -q --prune origin
    [ "$(git rev-parse 'v1.0.1^{commit}')" = "$(git rev-parse origin/main)" ]
    git merge-base --is-ancestor origin/main origin/next
    [ "$(git log -1 --format=%s origin/next)" = "Merge branch 'main' into next" ]
    remote_lacks_ref refs/heads/hotfix/v1.0.1
}

@test "topic, pr mode: finish pushes the branch and opens a pull request" {
    fake_gh
    git config workflow.finishTopic pr
    local_next
    git b start topic foo >/dev/null 2>&1
    commit_change a "work"

    run git b finish <<<"y"
    [ "$status" -eq 0 ]
    [ "$(cat "$GH_LOG")" = "pr create --base next --head foo --fill" ]
    # nothing merged locally or on the remote, and the branch stays
    [ "$(git rev-parse origin/foo)" = "$(git rev-parse foo)" ]
    [ "$(git rev-parse next)" = "$(git rev-parse origin/next)" ]
    [ "$(git branch --show-current)" = "foo" ]
}

@test "topic, pr mode: an open pull request is reported, not duplicated" {
    fake_gh "https://github.com/o/r/pull/7"
    git config workflow.finishTopic pr
    local_next
    git b start topic foo >/dev/null 2>&1
    commit_change a "work"

    run git b finish </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"already open: https://github.com/o/r/pull/7"* ]]
    [ ! -s "$GH_LOG" ]
}

@test "config: an invalid finishTopic warns and falls back to merge" {
    git config workflow.finishTopic squash
    run git b config
    [[ "$output" == *"finishTopic must be"* ]]
    [[ "$output" == *"finishTopic      merge"* ]]
}

@test "start: still allows tracked edits (carried like git switch -c)" {
    local_next
    echo wip >>a
    run git b start topic foo
    [ "$status" -eq 0 ]
    run git status --short
    [ "$output" = " M a" ]
}

@test "finish release: keeping a back-merge conflict prints how to publish" {
    local_next
    git b start release v1.1.0 >/dev/null 2>&1
    commit_change a "release fix"
    remote_commit next a

    run git b finish <<<$'y\nn'
    [ "$status" -ne 0 ]
    [[ "$output" == *"git push --atomic origin main next refs/tags/v1.1.0"* ]]
    [ "$(git branch --show-current)" = "next" ]
    git rev-parse --verify --quiet MERGE_HEAD >/dev/null
}

@test "rb-pull: a diverged protected branch stops instead of rebasing" {
    local_next
    git switch -q next
    commit_change b "local only"
    remote_commit next b
    before=$(git rev-parse next)

    run git rb-pull next
    [ "$status" -ne 0 ]
    [[ "$output" == *"diverged"* ]]
    [ "$(git rev-parse next)" = "$before" ]
}

@test "ps: still rebases onto commits someone else pushed" {
    git switch -qc feat
    commit_change a mine
    git push -qu origin feat
    remote_commit feat b
    commit_change a "mine too"

    run git ps
    [ "$status" -eq 0 ]
    [ "$(git log -1 --format=%s origin/feat)" = "mine too" ]
    [ "$(git log -1 --format=%s origin/feat~1)" = "upstream change on feat" ]
}

@test "sq: after squashing pushed commits it says how to publish" {
    git switch -qc feat
    commit_change a c1
    commit_change a c2
    git push -qu origin feat

    GIT_SEQUENCE_EDITOR=$(squash_editor) run git sq
    [ "$status" -eq 0 ]
    [[ "$output" == *"git ps force"* ]]
}

@test "strict: committing on a protected branch aborts" {
    git config workflow.strict true
    echo x >>a
    git add a
    run git qc "on main"
    [ "$status" -ne 0 ]
    [[ "$output" == *"workflow.strict"* ]]
}

@test "strict: a release version that isn't newer than the latest aborts" {
    git config workflow.strict true
    local_next
    run git b start release v0.9.0 </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"not newer"* ]]
}

@test "strict: a release branch that only exists on the remote blocks a second one" {
    git config workflow.strict true
    (cd "$SEED" && git push -q origin main:release/v1.1.0)
    local_next
    run git b start release v1.2.0 </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"one release branch at a time"* ]]
}

@test "an existing tag always stops start, strict or not" {
    local_next
    run git b start release v1.0.0 <<<"y"
    [ "$status" -ne 0 ]
    [[ "$output" == *"already exists"* ]]
}

@test "protected branches can't be deleted or finished" {
    run git b delete main -y
    [ "$status" -ne 0 ]
    run git b finish main
    [ "$status" -ne 0 ]
}

@test "pre: refuses when the branch is behind its remote" {
    local_next
    git b start release v1.1.0 >/dev/null 2>&1
    remote_commit release/v1.1.0 a
    run git b pre <<<$'y\ny'
    [ "$status" -ne 0 ]
    [[ "$output" == *"behind"* ]]
}

@test "versions compare numerically: v1.10.0 is newer than v1.9.0" {
    git config workflow.strict true
    local_next
    git tag -a v1.9.0 -m v1.9.0
    run git b start release v1.10.0
    [ "$status" -eq 0 ]
    run git b start release v1.8.0
    [ "$status" -ne 0 ]
    [[ "$output" == *"not newer"* ]]
}
