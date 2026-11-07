#!/usr/bin/env bats
# git b status: where you are, what's next, and what's left to do.

load test_helper

@test "status: on main in git flow, nothing open" {
    local_next
    run git b status
    [ "$status" -eq 0 ]
    [[ "$output" == *"gitflow flow: main and next; latest release v1.0.0."* ]]
    [[ "$output" == *"On main, the main branch."* ]]
    [[ "$output" == *"Next: git b start <type> (topic, release and hotfix)."* ]]
    [[ "$output" == *$'Open branches:\n  none'* ]]
    [[ "$output" != *"Left to do"* ]]
}

@test "status: a release branch, before and after its prereleases" {
    local_next
    git b start release v1.1.0 >/dev/null 2>&1
    commit_change a "release fix"

    run git b status
    [[ "$output" == *"On release/v1.1.0, the release branch for v1.1.0, into main."* ]]
    [[ "$output" == *"1 commit of its own; 1 not pushed."* ]]
    [[ "$output" == *"No prereleases yet."* ]]
    [[ "$output" == *"Next: git b pre to test it, then git b finish (merges it into main, tags v1.1.0, merges main back into next and pushes)."* ]]
    [[ "$output" == *"release   release/v1.1.0"* ]]

    git b pre -y </dev/null >/dev/null 2>&1
    run git b status
    [[ "$output" == *"Prereleases: v1.1.0-rc.1 (the tip is v1.1.0-rc.1)."* ]]
    [[ "$output" == *"Next: git b finish (merges it into main"* ]]

    commit_change a "another fix"
    run git b status
    [[ "$output" == *"Prereleases: v1.1.0-rc.1 (1 commit after v1.1.0-rc.1)."* ]]
    [[ "$output" == *"Next: git b pre to test what changed, or git b finish"* ]]
}

@test "status: a pull request that's open" {
    local_next
    fake_gh "OPEN https://github.com/o/r/pull/3"
    git b start topic foo >/dev/null 2>&1
    commit_change a "work"

    run git b status
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pull request: https://github.com/o/r/pull/3"* ]]
    [[ "$output" == *"Next: once it is merged, git b finish deletes the branch."* ]]
}

@test "status: a release merged on the forge but never tagged is left to do" {
    local_next
    fake_gh
    git b start release v1.1.0 >/dev/null 2>&1
    commit_change a "release fix"
    git push -q origin release/v1.1.0
    merge_pr release/v1.1.0

    run git b status
    [[ "$output" == *"Merged into origin/main."* ]]
    [[ "$output" == *"Next: git b finish tags v1.1.0 and deletes the branch."* ]]

    git switch -q next
    run git b status
    [[ "$output" == *$'Left to do:\n  release/v1.1.0 is merged into origin/main, but v1.1.0 isn\'t tagged: git b finish release/v1.1.0'* ]]
}

@test "status: a merged topic that's still around is left to do" {
    local_next
    fake_gh
    git b start topic foo >/dev/null 2>&1
    commit_change a "work"
    git push -q origin foo
    merge_pr foo next
    git switch -q next

    run git b status
    [[ "$output" == *"foo is merged into origin/next: git b delete foo"* ]]
}

@test "status: github flow, a prerelease of main waiting to be released" {
    drop_next
    git b pre v1.1.0 -y </dev/null >/dev/null 2>&1

    run git b status
    [[ "$output" == *"github flow: main; latest release v1.0.0."* ]]
    [[ "$output" == *"Next: git b release promotes v1.1.0-rc.1."* ]]

    git b start topic foo >/dev/null 2>&1
    run git b status
    [[ "$output" == *"v1.1.0 has prereleases but no release: git b release v1.1.0"* ]]
}

@test "status: an unknown argument is an error" {
    run git b status --bogus
    [ "$status" -ne 0 ]
    [[ "$output" == *"unknown argument: --bogus"* ]]
}
