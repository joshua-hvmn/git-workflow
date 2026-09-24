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

@test "hotfix: starts from main, and is merged back into next" {
    local_next
    remote_commit next b # next is ahead of main
    run git b start hotfix v1.0.1
    [ "$status" -eq 0 ]
    [ "$(git merge-base HEAD origin/main)" = "$(git rev-parse origin/main)" ]
    not_ancestor origin/next HEAD
}

@test "start: still allows tracked edits (carried like git switch -c)" {
    local_next
    echo wip >>a
    run git b start topic foo
    [ "$status" -eq 0 ]
    run git status --short
    [ "$output" = " M a" ]
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
