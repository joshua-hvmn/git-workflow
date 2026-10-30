#!/usr/bin/env bats
# Versions: tag prefixes, version files and bump keywords.

load test_helper

# Commit a file to next and push it: commit_on_next <file> <content>
commit_on_next() {
    local_next
    git switch -q next
    printf '%s\n' "$2" >"$1"
    git add "$1"
    git commit -qm "add $1"
    git push -q origin next
}

@test "start release minor/major, start hotfix patch: the next version after the latest release" {
    local_next
    run git b start release minor
    [ "$status" -eq 0 ]
    [[ "$output" == *"Next minor version: v1.1.0 (after v1.0.0)."* ]]
    [ "$(git branch --show-current)" = release/v1.1.0 ]

    git switch -q next
    git b delete release/v1.1.0 -y -f >/dev/null 2>&1
    git b start release major >/dev/null 2>&1
    [ "$(git branch --show-current)" = release/v2.0.0 ]

    git b start hotfix patch >/dev/null 2>&1
    [ "$(git branch --show-current)" = hotfix/v1.0.1 ]
}

@test "start: a version typed without its v gets one" {
    local_next
    run git b start release 1.1.0
    [ "$status" -eq 0 ]
    [[ "$output" != *"not a SemVer version"* ]]
    [ "$(git branch --show-current)" = release/v1.1.0 ]
}

@test "start release: offers to set VERSION, keeping its v, and commits it" {
    commit_on_next VERSION v1.0.0
    run git b start release minor -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"VERSION says 'v1.0.0'. Set it to v1.1.0 and commit? [Y/n]: y (-y)"* ]]
    [ "$(cat VERSION)" = v1.1.0 ]
    [ "$(git log -1 --format=%s)" = "bump version to v1.1.0" ]
    # pushed with the branch
    [ "$(git rev-parse origin/release/v1.1.0)" = "$(git rev-parse HEAD)" ]
    git diff --quiet HEAD
}

@test "start hotfix: a VERSION without a v stays without one, and answering no leaves it" {
    echo 1.0.0 >VERSION
    git add VERSION
    git commit -qm "add VERSION"
    git push -q origin main
    git b start hotfix patch -y >/dev/null 2>&1
    [ "$(cat VERSION)" = 1.0.1 ]

    git switch -q main
    run git b start hotfix v1.0.2 <<<"n"
    [ "$status" -eq 0 ]
    [ "$(git branch --show-current)" = hotfix/v1.0.2 ]
    [ "$(cat VERSION)" = 1.0.0 ]
}

@test "package.json: start sets the top-level version and nothing else" {
    git config workflow.versionFile package.json
    commit_on_next package.json '{
  "name": "demo",
  "engines": { "version": "9.9.9" },
  "scripts": { "v": "echo \"{\\\"version\\\": 1}\"" },
  "version": "1.0.0",
  "dependencies": {}
}'
    run git b start release minor -y
    [ "$status" -eq 0 ]
    [ "$(git log -1 --format=%s)" = "bump version to v1.1.0" ]
    grep -q '^  "version": "1.1.0",$' package.json
    grep -q '"engines": { "version": "9.9.9" }' package.json
    grep -q '"scripts": { "v": "echo' package.json
    [ "$(grep -c '"version"' package.json)" -eq 2 ]

    run git b pre -n
    [ "$status" -eq 0 ]
    [[ "$output" != *"package.json says"* ]]
    [[ "$output" == *"as 'v1.1.0-rc.1'"* ]]
}

@test "package.json: a version that doesn't match the release stops the prerelease" {
    git config workflow.versionFile package.json
    commit_on_next package.json '{ "name": "demo", "version": "1.0.0" }'
    git b start release v1.1.0 <<<"n" >/dev/null 2>&1

    run git b pre <<<"n"
    [ "$status" -ne 0 ]
    [[ "$output" == *"package.json says '1.0.0', but this release is v1.1.0."* ]]
    remote_lacks_ref refs/tags/v1.1.0-rc.1
}

@test "Cargo.toml: reads [package], not a dependency's version, and mentions Cargo.lock" {
    git config workflow.versionFile Cargo.toml
    commit_on_next Cargo.toml '[package]
name = "demo"
version = "1.0.0" # the crate

[dependencies]
serde = { version = "1" }
log.version = "0.4"

[[bin]]
name = "demo"'
    git switch -q next
    echo "lock" >Cargo.lock
    git add Cargo.lock
    git commit -qm lock
    git push -q origin next

    run git b start release minor -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"Cargo.lock records the version too"* ]]
    grep -q '^version = "1.1.0" # the crate$' Cargo.toml
    grep -q '^serde = { version = "1" }$' Cargo.toml
}

@test "Cargo.toml: a workspace's version is in [workspace.package]" {
    git config workflow.versionFile Cargo.toml
    commit_on_next Cargo.toml '[workspace]
members = ["a"]

[workspace.package]
version = "1.0.0"'
    git b start release patch -y >/dev/null 2>&1
    grep -q '^version = "1.0.1"$' Cargo.toml
}

@test "pyproject.toml: [project] wins over [tool.poetry], and single quotes stay" {
    git config workflow.versionFile pyproject.toml
    commit_on_next pyproject.toml "[tool.poetry]
version = \"0.9.0\"

[project]
name = \"demo\"
version = '1.0.0'"
    run git b start release minor -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"pyproject.toml says '1.0.0'"* ]]
    grep -q "^version = '1.1.0'$" pyproject.toml
    grep -q '^version = "0.9.0"$' pyproject.toml
}

@test "package.json: a version start can't place is said, and the branch still starts" {
    git config workflow.versionFile package.json
    commit_on_next package.json '{
  "version":
    "1.0.0"
}'
    run git b start release minor -y
    [ "$status" -eq 0 ]
    [[ "$output" == *"couldn't find where package.json keeps its version"* ]]
    [[ "$output" == *"Set package.json to v1.1.0 and commit it before git b pre."* ]]
    [ "$(git rev-parse origin/release/v1.1.0)" = "$(git rev-parse HEAD)" ]
    git diff --quiet HEAD
}

@test "pyproject.toml: a version that isn't in the file (setuptools-scm) is no mismatch" {
    git config workflow.versionFile pyproject.toml
    commit_on_next pyproject.toml '[project]
name = "demo"
dynamic = ["version"]'
    run git b start release minor -y
    [ "$status" -eq 0 ]
    [[ "$output" != *"pyproject.toml says"* ]]
    run git b pre -n
    [ "$status" -eq 0 ]
    [[ "$output" != *"pyproject.toml says"* ]]
}

@test "github flow: pre on main takes the version from package.json" {
    drop_next
    git config workflow.versionFile package.json
    printf '{\n  "version": "1.1.0"\n}\n' >package.json
    git add package.json
    git commit -qm "version"
    git push -q origin main

    run git b pre -n
    [ "$status" -eq 0 ]
    [[ "$output" == *"as 'v1.1.0-rc.1'"* ]]
}

@test "tagPrefix '': tags and branches are plain 1.2.3" {
    git config workflow.tagPrefix ""
    local_next
    run git b start release minor
    [ "$status" -eq 0 ]
    # v1.0.0 isn't a release under this prefix, so it starts from 0.0.0
    [ "$(git branch --show-current)" = release/0.1.0 ]
    commit_change a "release fix"

    run git b pre -y </dev/null
    [ "$status" -eq 0 ]
    remote_has_ref refs/tags/0.1.0-rc.1
    run git b finish -y </dev/null
    [ "$status" -eq 0 ]
    remote_has_ref refs/tags/0.1.0

    run git b start release v0.2.0
    [ "$(git branch --show-current)" = release/0.2.0 ]
}

@test "tagPrefix with a dash and a slash: one package's releases in a monorepo" {
    git config workflow.tagPrefix pkg-a/v
    local_next
    git b start release minor >/dev/null 2>&1
    [ "$(git branch --show-current)" = release/pkg-a/v0.1.0 ]
    commit_change a "release fix"

    git b pre -y </dev/null >/dev/null 2>&1
    git b pre -y </dev/null >/dev/null 2>&1
    run git b pre -l
    [ "$output" = $'pkg-a/v0.1.0-rc.1\npkg-a/v0.1.0-rc.2' ]

    run git b finish -y </dev/null
    [ "$status" -eq 0 ]
    [[ "$output" == *"Prereleases for pkg-a/v0.1.0: pkg-a/v0.1.0-rc.1 pkg-a/v0.1.0-rc.2"* ]]
    remote_has_ref refs/tags/pkg-a/v0.1.0

    run git b config
    [[ "$output" == *"tagPrefix        pkg-a/v  (git config)"* ]]
    [[ "$output" == *"tags pkg-a/vX.Y.Z on the merge"* ]]
}

@test "tagPrefix that can't start a tag is reported and ignored" {
    git config workflow.tagPrefix "bad prefix"
    run git b config
    [[ "$output" == *"workflow.tagPrefix (git config) 'bad prefix' can't start a tag name; using v."* ]]
    [[ "$output" == *"tagPrefix        v  (git config)"* ]]
}

@test ".gitworkflow: versionFile must stay inside the repository" {
    printf '[workflow]\n    versionFile = ../../outside\n' >.gitworkflow
    run git b config
    [[ "$output" == *"workflow.versionFile (.gitworkflow) '../../outside' must be a path inside the repository; using VERSION."* ]]
    [[ "$output" == *"versionFile      VERSION"* ]]

    printf '[workflow]\n    versionFile = /etc/passwd\n' >.gitworkflow
    run git b config
    [[ "$output" == *"must be a path inside the repository"* ]]
}
