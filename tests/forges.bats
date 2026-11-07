#!/usr/bin/env bats
# Forges: GitLab (glab), forges of your own, and where to watch a release run.

load test_helper

# The remote is GitLab-shaped (https://gitlab.com/up/proj), but points at
# remote.git through url.<path>.insteadOf
gitlab_remote() {
    git config --global url."$REMOTE_DIR".insteadOf https://gitlab.com/up/proj.git
    git remote set-url origin https://gitlab.com/up/proj.git
}

# A fake glab: `mr list` prints $GL_LIST (or $GL_MERGED with --merged),
# `api` says the project is 42, and everything else is logged to $GL_LOG
fake_glab() {
    command -v jq >/dev/null 2>&1 || skip "the gitlab forge needs jq"
    local bin="$BATS_TEST_TMPDIR/bin"
    GL_LOG="$BATS_TEST_TMPDIR/glab.log"
    GL_LIST="$BATS_TEST_TMPDIR/glab.list"
    GL_MERGED="$BATS_TEST_TMPDIR/glab.merged"
    : >"$GL_LOG"
    echo '[]' >"$GL_LIST"
    echo '[]' >"$GL_MERGED"
    mkdir -p "$bin"
    # shellcheck disable=SC2016 # the generated script expands these
    {
        echo '#!/bin/sh'
        echo 'case "$1 $2" in'
        echo '"mr list")'
        echo '    case "$*" in'
        echo "    *--merged*) cat '$GL_MERGED' ;;"
        echo "    *) cat '$GL_LIST' ;;"
        echo '    esac ;;'
        echo '"api "*) echo "{\"id\": 42}" ;;'
        echo "*) echo \"\$*\" >>'$GL_LOG' ;;"
        echo 'esac'
    } >"$bin/glab"
    chmod +x "$bin/glab"
    export PATH="$bin:$PATH" GL_LOG GL_LIST GL_MERGED
    use_prs
}

@test "gitlab: the forge is guessed from the upstream remote's URL" {
    gitlab_remote
    run git b config
    [ "$status" -eq 0 ]
    [[ "$output" == *"forge            gitlab  (guessed: 'origin' is on GitLab)"* ]]
}

@test "gitlab: a GitHub repository with gitlab in its name stays github" {
    git config --global url."$REMOTE_DIR".insteadOf https://github.com/me/gitlab-tools.git
    git remote set-url origin https://github.com/me/gitlab-tools.git
    run git b config
    [[ "$output" == *"forge            github"$'\n'* ]]
    git remote set-url origin git@gitlab.example.com:group/sub/proj.git
    run git b config
    [[ "$output" == *"forge            gitlab  (guessed: 'origin' is on GitLab)"* ]]
}

@test "gitlab: finishing a topic opens a merge request with glab" {
    gitlab_remote
    fake_glab
    local_next
    git b start topic foo >/dev/null 2>&1
    commit_change a "work"

    run git b finish <<<"y"
    [ "$status" -eq 0 ]
    [ "$(cat "$GL_LOG")" = "mr create -s foo -b next --fill -y --push=false -R https://gitlab.com/up/proj" ]
    [ "$(git rev-parse origin/foo)" = "$(git rev-parse foo)" ]
}

@test "gitlab: a merge request already open is shown, not opened again" {
    gitlab_remote
    fake_glab
    local_next
    git b start topic foo >/dev/null 2>&1
    commit_change a "work"
    echo '[{"state": "opened", "web_url": "https://gitlab.com/up/proj/-/merge_requests/7",
            "source_project_id": 1, "target_project_id": 1}]' >"$GL_LIST"

    run git b finish
    [ "$status" -eq 0 ]
    [[ "$output" == *"already open: https://gitlab.com/up/proj/-/merge_requests/7"* ]]
    [ ! -s "$GL_LOG" ]
}

@test "gitlab: finishing again after GitLab merged it, which git can't tell, deletes the branch" {
    drop_next
    protect_main
    gitlab_remote
    fake_glab
    git b start topic foo >/dev/null 2>&1
    commit_change a "one"
    git push -q -u origin foo
    (cd "$SEED" && git fetch -q && git switch -q -C main origin/main && git merge -q --squash origin/foo &&
        echo more >>a && git commit -qam "foo, edited (!1)" && AS_GITHUB=1 git push -q origin main)
    echo '[{"state": "merged", "web_url": "https://gitlab.com/up/proj/-/merge_requests/1",
            "source_project_id": 1, "target_project_id": 1}]' >"$GL_LIST"
    printf '[{"sha": "%s", "merge_commit_sha": null, "source_project_id": 1, "target_project_id": 1}]' \
        "$(git rev-parse foo)" >"$GL_MERGED"

    run git b finish <<<"y"
    [ "$status" -eq 0 ]
    [[ "$output" == *"merged into 'origin/main': https://gitlab.com/up/proj/-/merge_requests/1"* ]]
    [ ! -s "$GL_LOG" ]
    no_local_branch foo
}

@test "gitlab: a merge request from your fork names the fork as its head project" {
    drop_next
    FORK_DIR="$BATS_TEST_TMPDIR/fork.git"
    git clone -q --bare "$REMOTE_DIR" "$FORK_DIR"
    git config --global url."$REMOTE_DIR".insteadOf https://gitlab.com/up/proj.git
    git config --global url."$FORK_DIR".insteadOf https://gitlab.com/me/proj.git
    git remote set-url origin https://gitlab.com/me/proj.git
    git remote add upstream https://gitlab.com/up/proj.git
    git fetch -q --all --prune
    fake_glab
    git b start topic foo >/dev/null 2>&1
    commit_change a "work"

    run git b finish <<<"y"
    [ "$status" -eq 0 ]
    [ "$(cat "$GL_LOG")" = "mr create -s foo -b main --head https://gitlab.com/me/proj --fill -y --push=false -R https://gitlab.com/up/proj" ]
}

@test "gitlab: without glab, finish says what to install" {
    command -v glab >/dev/null 2>&1 && skip "glab is installed here"
    gitlab_remote
    use_prs
    local_next
    git b start topic foo >/dev/null 2>&1
    commit_change a "work"

    run git b finish <<<"y"
    [ "$status" -ne 0 ]
    [[ "$output" == *"needs the GitLab CLI (glab"* ]]
}

@test "a forge of your own, from ~/.config/git-workflow/forges" {
    mkdir -p "$XDG_CONFIG_HOME/git-workflow/forges"
    # shellcheck disable=SC2016 # written for the forge to expand
    printf '%s\n' \
        'forge_name() { printf mine; }' \
        'forge_require() { :; }' \
        'forge_pr_find() { :; }' \
        'forge_pr_merge_commit() { :; }' \
        'forge_pr_head() { :; }' \
        'forge_pr_create() { echo "create base=$1 branch=$2 remote=$3" >>"$BATS_TEST_TMPDIR/mine.log"; }' \
        >"$XDG_CONFIG_HOME/git-workflow/forges/mine.sh"
    git config workflow.forge mine
    use_prs
    local_next
    git b start topic foo >/dev/null 2>&1
    commit_change a "work"

    run git b config
    [[ "$output" == *"forge            mine  (git config)"* ]]
    run git b finish <<<"y"
    [ "$status" -eq 0 ]
    [ "$(cat "$BATS_TEST_TMPDIR/mine.log")" = "create base=next branch=foo remote=origin" ]
}

@test "a forge that doesn't exist is reported, and github used" {
    git config workflow.forge nope
    run git b config
    [[ "$output" == *"there's no forge 'nope'"* ]]
    [[ "$output" == *"forge            github"* ]]
}

@test "release run: GitHub Enterprise gets its Actions URL once workflow.forge says github" {
    git config --global url."$REMOTE_DIR".insteadOf https://ghe.example.com/o/r.git
    git remote set-url origin https://ghe.example.com/o/r.git
    local_next
    git b start release v1.1.0 >/dev/null 2>&1
    commit_change a "release fix"

    run git b pre -y </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" != *"Watch the release run"* ]]

    git config workflow.forge github
    run git b pre -y </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"Watch the release run: https://ghe.example.com/o/r/actions  (or: gh run watch)"* ]]
}

@test "release run: GitLab's pipelines" {
    gitlab_remote
    local_next
    git b start release v1.1.0 >/dev/null 2>&1
    commit_change a "release fix"

    run git b pre -y </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"Watch the release run: https://gitlab.com/up/proj/-/pipelines  (or: glab ci view)"* ]]
}
