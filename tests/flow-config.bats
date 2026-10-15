#!/usr/bin/env bats
# Flows as data: picking one, layering settings, custom flows and branch
# types, a repository's .gitworkflow, and git flow through pull requests.

load test_helper

# .gitworkflow <lines...>: write the repository's file, one line per argument
repo_file() {
    printf '%s\n' "$@" >.gitworkflow
}

@test "flow: a next branch means git flow, and it says it guessed" {
    run git b config
    [ "$status" -eq 0 ]
    [[ "$output" == *"flow             gitflow  (guessed: there's a 'next' branch)"* ]]
    [[ "$output" == *"git flow: main + next, release and hotfix branches"* ]]
    [[ "$output" == *"devBranch        next  (flow gitflow)"* ]]
    [[ "$output" == *"release   release/    from next into main by merge, tags vX.Y.Z on the merge, merged back into next, one at a time"* ]]
}

@test "flow: a develop branch means git flow with develop as the dev branch" {
    git push -q origin main:develop :next
    git fetch -q --prune origin
    run git b config
    [[ "$output" == *"flow             gitflow  (guessed: there's a 'develop' branch)"* ]]
    [[ "$output" == *"devBranch        develop  (the 'develop' branch)"* ]]
    run git b start topic foo
    [ "$status" -eq 0 ]
    [[ "$output" == *"from 'develop'"* ]]
}

@test "flow: workflow.flow picks it, whatever the branches say" {
    git config workflow.flow github
    run git b config
    [[ "$output" == *"flow             github  (git config)"* ]]
    [[ "$output" == *"devBranch        main"* ]]
}

@test "flow: an unknown flow warns, lists the flows, and uses github" {
    git config workflow.flow nope
    run git b config
    [[ "$output" == *"there's no flow named 'nope'"*"The flows: gitflow github"* ]]
    [[ "$output" == *"flow             github"* ]]
}

@test "flow: 2.x settings still work" {
    git config workflow.devBranch main # 2.x's trunk mode
    git config workflow.releasePrefix rel/
    run git b config
    [[ "$output" == *"flow             github  (workflow.devBranch is mainBranch)"* ]]

    git config --unset workflow.devBranch
    run git b config
    [[ "$output" == *"release   rel/ "* ]]
}

@test "repo file: .gitworkflow picks the flow and adjusts it" {
    repo_file '[workflow]' 'flow = github' '[workflow "hotfix"]' 'prefix = fix/'
    run git b config
    [[ "$output" == *"flow             github  (.gitworkflow)"* ]]
    [[ "$output" == *"hotfix    fix/ "* ]]
    [[ "$output" == *"repository file  $(git rev-parse --show-toplevel)/.gitworkflow"* ]]
}

@test "repo file: it beats your global config, and your repo config beats it" {
    git config --global workflow.flow gitflow
    repo_file '[workflow]' 'flow = github'
    run git b config
    [[ "$output" == *"flow             github  (.gitworkflow)"* ]]

    git config workflow.flow gitflow
    run git b config
    [[ "$output" == *"flow             gitflow  (git config)"* ]]
}

@test "repo file: it can't set your remotes, and bad values are refused, not used" {
    repo_file '[workflow]' 'remote = evil' 'integrate = sideways' \
        '[workflow "release"]' 'prefix = --upload-pack=x/' \
        '[workflow "Weird"]' 'into = main' '[workflow "topic"]' 'colour = red'
    run git b config
    [[ "$output" == *"workflow.remote can't be set in .gitworkflow; ignored."* ]]
    [[ "$output" == *"workflow.integrate (.gitworkflow) must be pr or merge, not 'sideways'"* ]]
    [[ "$output" == *"workflow.release.prefix (.gitworkflow) '--upload-pack=x/' can't start a branch name; ignored the 'release' type."* ]]
    [[ "$output" == *"workflow.Weird.into (.gitworkflow): a branch type is lowercase"* ]]
    [[ "$output" == *"workflow.topic.colour (.gitworkflow) is not a setting git-workflow knows"* ]]
    [[ "$output" == *"remote           origin"* ]]
    [[ "$output" != *"release   "* ]]
}

@test "repo file: includes in it aren't followed" {
    printf '[workflow]\n    flow = github\n' >"$BATS_TEST_TMPDIR/elsewhere"
    repo_file '[include]' "path = $BATS_TEST_TMPDIR/elsewhere"
    run git b config
    [[ "$output" == *"flow             gitflow  (guessed"* ]]
}

@test "repo file: control characters in values are dropped" {
    repo_file '[workflow]' "description = nice$(printf '\033[2J')title"
    run git b config
    [[ "$output" == *"nice[2Jtitle"* ]]
    [[ "$output" != *$'\033'* ]]
}

@test "custom type: a feature/ type from the dev branch, defined in .gitworkflow" {
    repo_file '[workflow "feature"]' 'prefix = feature/' 'from = dev' 'into = dev'
    run git b start feature login
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = "feature/login" ]
    commit_change a "login"

    run git b finish <<<$'y\ny'
    [ "$status" -eq 0 ]
    git fetch -q origin
    [ "$(git log -1 --format=%s origin/next)" = "Merge branch 'feature/login' into next" ]
    no_local_branch feature/login
}

@test "custom type: into = none removes one of the flow's types" {
    repo_file '[workflow "hotfix"]' 'into = none'
    run git b config --types
    [ "$output" = $'topic\nrelease' ]
    run git b start hotfix v1.0.1
    [ "$status" -ne 0 ]
    [[ "$output" == *"the gitflow flow has no 'hotfix' branches. Its types: topic and release."* ]]
}

@test "custom flow: a file in ~/.config/git-workflow/flows is a flow" {
    mkdir -p "$XDG_CONFIG_HOME/git-workflow/flows"
    cat >"$XDG_CONFIG_HOME/git-workflow/flows/oneflow" <<'FLOW'
[workflow]
    description = one long-lived branch; releases merge back into it
[workflow "topic"]
    into = main
    from = main
[workflow "release"]
    prefix = release/
    from = main
    into = main
    tag = tip
FLOW
    git config workflow.flow oneflow
    run git b config
    [[ "$output" == *"flow             oneflow  (git config)"* ]]
    [[ "$output" == *"one long-lived branch"* ]]

    git b start release v1.1.0 >/dev/null 2>&1
    commit_change a "release fix"
    tested=$(git rev-parse HEAD)
    run git b finish <<<$'y\ny'
    [ "$status" -eq 0 ]
    git fetch -q origin
    [ "$(git rev-parse 'v1.1.0^{commit}')" = "$tested" ]
    git merge-base --is-ancestor "$tested" origin/main
}

@test "custom flow: a flow file can't pick a flow or set your remotes" {
    mkdir -p "$XDG_CONFIG_HOME/git-workflow/flows"
    printf '[workflow]\n    flow = gitflow\n    upstream = evil\n[workflow "topic"]\n    into = main\n' \
        >"$XDG_CONFIG_HOME/git-workflow/flows/odd"
    git config workflow.flow odd
    run git b config
    [[ "$output" == *"workflow.flow can't be set in flow odd; ignored."* ]]
    [[ "$output" == *"workflow.upstream can't be set in flow odd; ignored."* ]]
}

@test "single: git flow's one-release-at-a-time is a type setting" {
    git config workflow.strict true
    git b start release v1.1.0 >/dev/null 2>&1
    git switch -q main
    run git b start release v1.2.0
    [ "$status" -ne 0 ]
    [[ "$output" == *"one release branch at a time"* ]]

    git config workflow.release.single false
    run git b start release v1.2.0
    [ "$status" -eq 0 ]
}

@test "finish: a branch of no type in the flow is refused" {
    repo_file '[workflow "topic"]' 'into = none'
    git switch -qc foo
    run git b finish </dev/null
    [ "$status" -ne 0 ]
    [[ "$output" == *"'foo' isn't a branch of any type in the gitflow flow"* ]]
}

@test "finish release: commits after the last prerelease are flagged" {
    git config workflow.strict true
    git b start release v1.1.0 >/dev/null 2>&1
    commit_change a "fix"
    git b pre <<<$'y\ny' >/dev/null 2>&1
    commit_change a "untested"

    run git b finish <<<"y"
    [ "$status" -ne 0 ]
    [[ "$output" == *"commits after v1.1.0-rc.1 that no prerelease tested"* ]]
}

@test "git flow, pull requests: a release opens one into main, then tags the merge and opens the back-merge" {
    fake_gh
    git b start release v1.1.0 >/dev/null 2>&1
    commit_change a "release fix"

    run git b finish <<<"y"
    [ "$status" -eq 0 ]
    [ "$(cat "$GH_LOG")" = "pr create --base main --head release/v1.1.0 --title Release v1.1.0 --body Once it's merged, \`git b finish release/v1.1.0\` tags the merge as v1.1.0." ]
    remote_lacks_ref refs/tags/v1.1.0

    merge_pr release/v1.1.0
    : >"$GH_LOG"
    run git b finish release/v1.1.0 <<<$'y\ny\ny'
    [ "$status" -eq 0 ]
    git fetch -q origin
    [ "$(git rev-parse 'v1.1.0^{commit}')" = "$(git rev-parse origin/main)" ]
    [ "$(cat "$GH_LOG")" = "pr create --base next --head main --title Merge main into next after v1.1.0 --body Back-merge of v1.1.0. Merge it with a merge commit, so next has the release and its tag." ]
    no_local_branch release/v1.1.0
    remote_lacks_ref refs/heads/release/v1.1.0
}

@test "git flow, pull requests: a squash-merged release is tagged on the commit gh reports" {
    fake_gh
    git b start release v1.1.0 >/dev/null 2>&1
    commit_change a "release fix"
    git push -q origin release/v1.1.0
    merge_pr release/v1.1.0 main squash
    git fetch -q origin
    gh_view "MERGED https://github.com/o/r/pull/3"
    gh_merge "$(git rev-parse origin/main)"

    run git b finish <<<$'y\nn\ny'
    [ "$status" -eq 0 ]
    git fetch -q origin
    [ "$(git rev-parse 'v1.1.0^{commit}')" = "$(git rev-parse origin/main)" ]
}

@test "git flow, mixed: topics by pull request, releases merged locally" {
    fake_gh
    git config workflow.release.integrate merge
    git b start topic foo >/dev/null 2>&1
    commit_change a "work"
    run git b finish <<<"y"
    [ "$(cat "$GH_LOG")" = "pr create --base next --head foo --fill" ]

    git switch -q main
    git b start release v1.1.0 >/dev/null 2>&1
    commit_change b "release fix"
    run git b finish <<<$'y\ny'
    [ "$status" -eq 0 ]
    remote_has_ref refs/tags/v1.1.0
    [ "$(cat "$GH_LOG")" = "pr create --base next --head foo --fill" ]
}

@test "config --types: the type names, for completion" {
    run git b config --types
    [ "$status" -eq 0 ]
    [ "$output" = $'topic\nrelease\nhotfix' ]
}
