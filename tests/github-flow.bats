#!/usr/bin/env bats
# GitHub flow: pull requests into main, releasing from main, forks.

load test_helper

# A GitHub flow repository: no next branch, and main only takes pull requests
github_flow() {
    drop_next
    protect_main
}

# Put a VERSION file on main, the way it would get there: through a pull request
version_on_main() {
    git b start topic bump >/dev/null 2>&1
    echo "$1" >VERSION
    git add VERSION
    git commit -qm "bump version to $1"
    git push -q -u origin bump
    merge_pr bump
    git switch -q main
    git branch -q -D bump
    git sync >/dev/null 2>&1
}

@test "github flow: with no next branch, it's the flow, and finish opens pull requests" {
    drop_next
    use_prs
    run git b config
    [ "$status" -eq 0 ]
    [[ "$output" == *"flow             github  (guessed: no 'next' or 'develop' branch)"* ]]
    [[ "$output" == *"devBranch        main"* ]]
    [[ "$output" == *"integrate        pr"* ]]
    [[ "$output" == *"topic     (no prefix) from main into main by pull request"* ]]
    [[ "$output" == *"hotfix    hotfix/     from latest-release into main by pull request, tags vX.Y.Z on its tested tip"* ]]
}

@test "github flow: mainBranch defaults to the remote's default branch" {
    git push -q origin main:trunk
    git remote set-head origin trunk
    run git b config
    [[ "$output" == *"mainBranch       trunk  (the remote's default branch)"* ]]
}

@test "github flow: there are no release branches; start release says how to release" {
    drop_next
    run git b start release v1.1.0
    [ "$status" -ne 0 ]
    [[ "$output" == *"the github flow has no 'release' branches"* ]]
    [[ "$output" == *"git b pre"*"git b release"* ]]
}

@test "github flow: finishing a topic opens a pull request into main" {
    github_flow
    fake_gh
    git b start topic foo >/dev/null 2>&1
    commit_change a "work"

    run git b finish <<<"y"
    [ "$status" -eq 0 ]
    [ "$(cat "$GH_LOG")" = "pr create --base main --head foo --fill" ]
    [ "$(git rev-parse origin/foo)" = "$(git rev-parse foo)" ]
    [[ "$output" == *"Once it's merged"* ]]
}

@test "github flow: finishing again after a merge-commit merge deletes the branch, no gh needed" {
    github_flow
    use_prs
    git b start topic foo >/dev/null 2>&1
    commit_change a "work"
    git push -q -u origin foo
    merge_pr foo

    run git b finish <<<"y"
    [ "$status" -eq 0 ]
    no_local_branch foo
    [ "$(git branch --show-current)" = "main" ]
    [ "$(git rev-parse main)" = "$(git rev-parse origin/main)" ]
}

@test "github flow: finishing again after a squash merge deletes the branch, no gh needed" {
    github_flow
    use_prs
    git b start topic foo >/dev/null 2>&1
    commit_change a "one"
    commit_change b "two"
    git push -q -u origin foo
    merge_pr foo main squash

    run git b finish <<<"y"
    [ "$status" -eq 0 ]
    no_local_branch foo
}

@test "github flow: a merged pull request gh knows about, but git can't tell, is cleaned up" {
    github_flow
    fake_gh
    git b start topic foo >/dev/null 2>&1
    commit_change a "one"
    git push -q -u origin foo
    # Merged with a change on top that the branch doesn't have
    (cd "$SEED" && git fetch -q && git switch -q -C main origin/main && git merge -q --squash origin/foo &&
        echo more >>a && git commit -qam "foo, edited (#1)" && AS_GITHUB=1 git push -q origin main)
    gh_view "MERGED https://github.com/o/r/pull/1"
    gh_head "$(git rev-parse foo)"

    run git b finish <<<"y"
    [ "$status" -eq 0 ]
    [[ "$output" == *"merged into 'origin/main': https://github.com/o/r/pull/1"* ]]
    [ ! -s "$GH_LOG" ]
    no_local_branch foo
}

@test "github flow: a branch name used again after its pull request merged opens a new one" {
    github_flow
    fake_gh
    git b start topic foo >/dev/null 2>&1
    commit_change a "old work"
    old=$(git rev-parse HEAD)
    commit_change a "new work"
    gh_view "MERGED https://github.com/o/r/pull/1"
    gh_head "$old"

    run git b finish <<<"y"
    [ "$status" -eq 0 ]
    [[ "$output" == *"merged without its newest commits"* ]]
    [ "$(cat "$GH_LOG")" = "pr create --base main --head foo --fill" ]
}

@test "finish: when gh can't be asked, it stops instead of pushing the branch" {
    github_flow
    broken_gh
    git b start topic foo >/dev/null 2>&1
    commit_change a "work"
    git push -q -u origin foo
    # squash-merged with an extra change, so only gh could tell, then deleted
    (cd "$SEED" && git fetch -q && git switch -q -C main origin/main && git merge -q --squash origin/foo &&
        echo more >>a && git commit -qam "foo, edited (#1)" && AS_GITHUB=1 git push -q origin main &&
        git push -q origin --delete foo)
    git fetch -q --prune

    run git b finish <<<"y"
    [ "$status" -ne 0 ]
    [[ "$output" == *"couldn't look up the pull requests for 'foo'"* ]]
    remote_lacks_ref refs/heads/foo
}

@test "finish: a branch with no commits of its own isn't merged" {
    github_flow
    fake_gh
    git b start topic foo >/dev/null 2>&1

    run git b finish <<<"y"
    [ "$status" -ne 0 ]
    [[ "$output" == *"there's nothing to finish"* ]]
    [ "$(git branch --show-current)" = "foo" ]
}

@test "github flow: a hotfix with no commits doesn't tag the last release again" {
    drop_next
    git b start hotfix v1.0.1 >/dev/null 2>&1

    run git b finish <<<$'y\ny'
    [ "$status" -ne 0 ]
    [[ "$output" == *"already released as v1.0.0"* ]]
    remote_lacks_ref refs/tags/v1.0.1
    no_local_tag v1.0.1
}

@test "delete: a squash-merged branch is merged, no -f needed" {
    drop_next
    git b start topic foo >/dev/null 2>&1
    commit_change a "one"
    commit_change a "two"
    git push -q -u origin foo
    merge_pr foo main squash
    git switch -q main

    run git b delete foo <<<"y"
    [ "$status" -eq 0 ]
    no_local_branch foo
}

@test "delete: a branch with work that isn't on main still needs -f" {
    drop_next
    git b start topic foo >/dev/null 2>&1
    commit_change a "one"
    git switch -q main

    run git b delete foo <<<"y"
    [ "$status" -ne 0 ]
    [[ "$output" == *"aren't merged into main."* ]]
}

@test "github flow: ps and qc p refuse to push main, before committing" {
    github_flow
    use_prs
    run git ps
    [ "$status" -ne 0 ]
    [[ "$output" == *"'main' takes changes through pull requests"* ]]

    echo change >>a
    git add a
    before=$(git rev-parse HEAD)
    run git qc p "change"
    [ "$status" -ne 0 ]
    [ "$(git rev-parse HEAD)" = "$before" ]
}

@test "github flow: a hotfix starts from the latest release, not main" {
    drop_next
    remote_commit main b # unreleased work on main
    run git b start hotfix v1.0.1
    [ "$status" -eq 0 ]
    [ "$(git merge-base HEAD v1.0.0)" = "$(git rev-parse 'v1.0.0^{commit}')" ]
    not_ancestor origin/main HEAD
}

@test "github flow: a hotfix finishes through a pull request, then tags its tested tip" {
    github_flow
    fake_gh
    git b start hotfix v1.0.1 >/dev/null 2>&1
    commit_change a "the fix"
    tested=$(git rev-parse HEAD)

    run git b finish <<<"y"
    [ "$status" -eq 0 ]
    [[ "$(cat "$GH_LOG")" == "pr create --base main --head hotfix/v1.0.1 --title Hotfix v1.0.1 --body Merge with a merge commit"* ]]
    remote_lacks_ref refs/tags/v1.0.1

    remote_commit main b # merged to main while the pull request was open
    merge_pr hotfix/v1.0.1
    run git b finish <<<$'y\ny'
    [ "$status" -eq 0 ]
    git fetch -q origin
    [ "$(git rev-parse 'v1.0.1^{commit}')" = "$tested" ]
    remote_has_ref refs/tags/v1.0.1
    no_local_branch hotfix/v1.0.1
}

@test "github flow: a squash-merged hotfix pull request is refused, not tagged" {
    github_flow
    use_prs
    git b start hotfix v1.0.1 >/dev/null 2>&1
    commit_change a "the fix"
    git push -q origin hotfix/v1.0.1
    merge_pr hotfix/v1.0.1 main squash

    run git b finish </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"as a squash or rebase"* ]]
    [[ "$output" == *"git b pre v1.0.1"* ]]
    remote_lacks_ref refs/tags/v1.0.1
    no_local_tag v1.0.1
}

@test "github flow: pre on main takes the version from VERSION and pushes only the tag" {
    github_flow
    use_prs
    version_on_main v1.1.0

    run git b pre <<<"y"
    [ "$status" -eq 0 ]
    [[ "$output" == *"Pushed prerelease 'v1.1.0-rc.1'"* ]]
    [[ "$output" == *"release v1.1.0"* ]]
    git fetch -q origin
    [ "$(git rev-parse 'v1.1.0-rc.1^{commit}')" = "$(git rev-parse origin/main)" ]
}

@test "github flow: pre on main takes an explicit version, and brings main up to date first" {
    github_flow
    remote_commit main b
    run git b pre v1.1.0 <<<"y"
    [ "$status" -eq 0 ]
    git fetch -q origin
    [ "$(git rev-parse 'v1.1.0-rc.1^{commit}')" = "$(git rev-parse origin/main)" ]
}

@test "github flow: pre on main without a version says how to name one" {
    github_flow
    run git b pre </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"no version to prerelease"* ]]
}

@test "github flow: pre on main refuses local commits main doesn't have" {
    github_flow
    use_prs
    commit_change a "local only"
    run git b pre v1.1.0 </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"local commit(s) that aren't on 'origin/main'"* ]]
    [[ "$output" == *"through a pull request"* ]]
    remote_lacks_ref refs/tags/v1.1.0-rc.1
}

@test "github flow: release promotes the newest prerelease's commit, after main moved on" {
    github_flow
    use_prs
    version_on_main v1.1.0
    git b pre <<<"y" >/dev/null 2>&1
    tested=$(git rev-parse HEAD)
    remote_commit main b # merged after the prerelease

    run git b release <<<"y"
    [ "$status" -eq 0 ]
    [[ "$output" == *"1 commit(s) after v1.1.0-rc.1; they aren't in v1.1.0"* ]]
    git fetch -q origin
    [ "$(git rev-parse 'v1.1.0^{commit}')" = "$tested" ]
    remote_has_ref refs/tags/v1.1.0
}

@test "github flow: release promotes the prerelease cut last, whatever its label" {
    github_flow
    use_prs
    version_on_main v1.1.0
    GIT_COMMITTER_DATE="2026-01-01T00:00:00Z" git b pre <<<"y" >/dev/null 2>&1 # v1.1.0-rc.1
    remote_commit main b
    git sync >/dev/null 2>&1
    GIT_COMMITTER_DATE="2026-01-02T00:00:00Z" git b pre beta <<<"y" >/dev/null 2>&1
    tested=$(git rev-parse HEAD)

    run git b release <<<"y"
    [ "$status" -eq 0 ]
    git fetch -q origin
    [ "$(git rev-parse 'v1.1.0^{commit}')" = "$tested" ]
}

@test "github flow: release -n changes nothing" {
    github_flow
    git b pre v1.1.0 <<<"y" >/dev/null 2>&1
    run git b release -n
    [ "$status" -eq 0 ]
    [[ "$output" == *"Would tag"*"(v1.1.0-rc.1) as 'v1.1.0'"* ]]
    remote_lacks_ref refs/tags/v1.1.0
}

@test "github flow: release with no prerelease is untested, so strict refuses it" {
    github_flow
    git config workflow.strict true
    run git b release v1.1.0 </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"no prereleases were cut for v1.1.0"* ]]
    remote_lacks_ref refs/tags/v1.1.0
}

@test "github flow: release with nothing to promote says what to do" {
    github_flow
    run git b release </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"no prerelease to promote"* ]]
}

@test "git flow: release says it releases through branches instead" {
    run git b release v1.1.0 </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"the gitflow flow doesn't release from main"* ]]
}

@test "fork: topics start from upstream's main and go to your fork" {
    drop_next
    use_fork
    remote_commit main b # upstream moved on after you forked

    run git b start topic foo
    [ "$status" -eq 0 ]
    [ "$(git merge-base HEAD upstream/main)" = "$(git rev-parse upstream/main)" ]
    git ls-remote --exit-code "$FORK_DIR" refs/heads/foo >/dev/null
    remote_lacks_ref refs/heads/foo
}

@test "fork: the pull request goes to upstream, from your fork's branch" {
    drop_next
    use_fork
    fake_gh
    git b start topic foo >/dev/null 2>&1
    commit_change a "work"

    run git b finish <<<"y"
    [ "$status" -eq 0 ]
    [ "$(cat "$GH_LOG")" = "pr create --base main --head me:foo --fill --repo up/proj" ]
    git ls-remote --exit-code "$FORK_DIR" refs/heads/foo >/dev/null
}

@test "fork: sync brings main up to date from upstream, and tags come from upstream" {
    drop_next
    use_fork
    remote_commit main b
    (cd "$SEED" && git tag -a v1.0.1 -m v1.0.1 origin/main && git push -q origin v1.0.1)

    run git sync
    [ "$status" -eq 0 ]
    [ "$(git rev-parse main)" = "$(git rev-parse upstream/main)" ]
    tag_exists_locally v1.0.1
}

@test "fork: sync ignores the fork's own copy of a tag" {
    drop_next
    use_fork
    remote_commit main b
    git -C "$FORK_DIR" tag -a v1.1.0-rc.1 -m "a test in the fork" main
    (cd "$SEED" && git tag -a v1.1.0-rc.1 -m upstream origin/main && git push -q origin v1.1.0-rc.1)

    run git sync
    [ "$status" -eq 0 ]
    [ "$(git rev-parse 'v1.1.0-rc.1^{commit}')" = "$(git rev-parse upstream/main)" ]
}
