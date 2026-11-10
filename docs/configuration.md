# Flows and configuration

git-workflow's settings: the flows, how `finish` integrates, every `workflow.*` key, a
repository's `.gitworkflow`, flows and forges of your own, versions, and the guardrails.
`git b config` shows the flow and every setting with where it came from.

## Flows

A flow decides where each kind of branch starts and where `finish` takes it. Two ship:

- **`gitflow`**: `main` holds releases and `next` collects finished work. Topics go into
  `next`; `release/vX.Y.Z` branches go from `next` into `main`, tagged on the merge, and `main`
  is merged back into `next`; `hotfix/vX.Y.Z` branches do the same from `main`.
- **`github`**: everything starts from `main` and goes back into it. A release is a tag:
  [`pre` and `release` on `main`](releasing.md#releasing-from-main). `hotfix/vX.Y.Z` branches start from the
  latest release (since `main` already has unreleased work) and are tagged on their tested tip.

Unless you pick one with `workflow.flow`, it's guessed: a `next` branch (or `develop`, which
then becomes the dev branch) means `gitflow`, anything else `github`. `git b config` shows the
flow, why, and where every setting came from.

## How `finish` integrates

By default **`finish` opens a pull request** (with `gh`), so it never pushes to `main` or the
dev branch, and works on repositories where those only take pull requests. Run `finish` again
once it's merged: it deletes the branch and, for a release or hotfix, tags it and pushes only
the tag. `integrate = merge` merges locally instead, and pushes everything in one atomic push.
Set it for the whole flow, or per branch type:

```sh
git config workflow.integrate merge          # this repository: merge locally
git config workflow.release.integrate merge  # only releases (and their back-merge)
```

To merge locally on your own repositories and nowhere else, let git pick by owner with
`includeIf` (Git 2.36 or newer):

```ini
# ~/.gitconfig
[includeIf "hasconfig:remote.*.url:git@github.com:you/**"]
    path = ~/.config/git-workflow/mine   # contains: [workflow] integrate = merge
```

## Settings

Every setting is a `workflow.*` key. These apply to the whole flow:

| Key                        | Default                                | Meaning                                                                        |
| -------------------------- | -------------------------------------- | ------------------------------------------------------------------------------ |
| `workflow.flow`            | guessed (above)                        | `gitflow`, `github`, or a flow of your own                                     |
| `workflow.mainBranch`      | the remote's default branch            | production branch; stable tags live here                                       |
| `workflow.devBranch`       | the flow's (`next`), else `mainBranch` | integration branch                                                             |
| `workflow.integrate`       | `pr`                                   | `pr`: finish opens a pull request. `merge`: it merges locally                  |
| `workflow.releaseFromMain` | the flow's                             | `true`: `pre` and `release` tag `main` directly                                |
| `workflow.remote`          | `origin`                               | where your branches go (your fork, if you use one)                             |
| `workflow.upstream`        | `upstream` if it exists, else `remote` | where main, dev and the tags live; pull requests go here                       |
| `workflow.forge`           | `gitlab` if the URL says so, `github`  | what opens pull requests: `github` (`gh`), `gitlab` (`glab`), [yours](#forges) |
| `workflow.prereleaseLabel` | `rc`                                   | default label for `git b pre`                                                  |
| `workflow.strict`          | `false`                                | `true`: flow violations abort. `false`: warn and ask                           |
| `workflow.versionFile`     | `VERSION`                              | must match the version being tagged ([formats](#versions)). `""` disables      |
| `workflow.tagPrefix`       | `v`                                    | what comes before `X.Y.Z` in tags and branch names ([versions](#versions))     |
| `workflow.protected`       | —                                      | extra protected branches (multi-valued, `git config --add`)                    |

Each branch type is a set of `workflow.<type>.<key>` settings (`workflow.release.prefix`):

| Key         | Values                          | Meaning                                                                |
| ----------- | ------------------------------- | ---------------------------------------------------------------------- |
| `prefix`    | e.g. `release/`                 | branch name prefix; one type has none (`topic`)                        |
| `from`      | `main`, `dev`, `latest-release` | what `start` branches from                                             |
| `into`      | `main`, `dev`, `none`           | what `finish` integrates into; `none` removes the type                 |
| `integrate` | `pr`, `merge`                   | overrides `workflow.integrate` for this type                           |
| `tag`       | `none`, `merge`, `tip`          | tag `vX.Y.Z` (from the branch name) on the merge, or on the tested tip |
| `backMerge` | `none`, `dev`                   | after integrating into `main`, merge `main` into `dev`                 |
| `single`    | `false`, `true`                 | one branch of this type open at a time                                 |

They're read in layers, and a later one wins:

1. the flow file: `share/flows/<flow>`, or `~/.config/git-workflow/flows/<flow>`
2. what the repository looks like: its default branch, a `develop` branch
3. your global git config (`~/.gitconfig`, and what it includes)
4. the repository's `.gitworkflow` file
5. the repository's git config (`.git/config`)
6. `git -c workflow.<key>=<value>`

So a repository's `.gitworkflow` beats your global defaults, and your own clone's config beats
it. Leave `mainBranch` and `devBranch` unset globally: they're worked out per repository.

```sh
git config workflow.flow github                 # this repository uses GitHub flow
git config workflow.strict true                 # this repository: no exceptions
git config workflow.hotfix.prefix fix/          # one branch type setting
git -c workflow.strict=true b finish            # one-off
git b config                                    # the flow, and every setting with its source
```

## A repository's `.gitworkflow`

A repository can commit its flow, in the same format, so everyone's `git b` follows it:

```ini
# .gitworkflow
[workflow]
    flow = gitflow
[workflow "release"]
    integrate = merge
```

It's someone else's file, so it's treated as data: every value is checked against the lists
above (a bad one is reported and ignored), branch names must be valid ones, includes aren't
followed, and it can't set `remote` or `upstream`, which are about your clone. This project's
own [`.gitworkflow`](../.gitworkflow) is an example.

## Writing a flow

A flow is a file of these settings. Put one in `~/.config/git-workflow/flows/<name>` and pick it
with `workflow.flow <name>`; it can define its own branch types. Starting from a shipped flow
([`share/flows/`](../share/flows/)) is easiest. This one keeps a single long-lived branch and
releases through release branches tagged on their tested tip:

```ini
# ~/.config/git-workflow/flows/oneflow
[workflow]
    description = one long-lived branch; releases merge back into it
[workflow "topic"]
    from = main
    into = main
[workflow "release"]
    prefix = release/
    from = main
    into = main
    tag = tip
```

A flow that needs something these settings can't express (cherry-picking fixes onto release
branches, say) is a new value for one of them, in `share/flow.sh`. Pull requests go through a
[forge](#forges).

## Versions

A version is SemVer after the tag prefix, `workflow.tagPrefix` (default `v`), in tags and in
the names of versioned branches. `""` makes them `1.2.3`; a path makes them one package's of
several in a monorepo:

```sh
git config workflow.tagPrefix pkg-a/v   # release/pkg-a/v1.2.0, tagged pkg-a/v1.2.0, rc's pkg-a/v1.2.0-rc.1
```

A version typed without its prefix gets it: `git b start release 1.2.0` is `release/v1.2.0`.
In place of the version, `major`, `minor` or `patch` names the next one after the latest
release (after `0.0.0` when there's none): `git b start release minor`.

`workflow.versionFile` (default `VERSION`) is the file that holds the project's version, a path
inside the repository. When it exists, `pre`, `release` and `finish` check that it matches the
version being tagged, with or without a `v`, before anything is public. On a new release or
hotfix branch, `start` offers to set it and commit `bump version to vX.Y.Z`. Its name says how
to read it:

| File             | The version                                 |
| ---------------- | ------------------------------------------- |
| `package.json`   | the top-level `"version"`                   |
| `Cargo.toml`     | `[package]`'s, else `[workspace.package]`'s |
| `pyproject.toml` | `[project]`'s, else `[tool.poetry]`'s       |
| anything else    | the whole file: `1.2.3` or `v1.2.3`         |

They're read with awk, so there's nothing to install and nothing in the file runs. A file
with no version of its own (setuptools-scm's dynamic version, say) is no mismatch. When a lock
file records the version too (`Cargo.lock`, `package-lock.json`), `start` says so: update it
with its own tool and commit before `git b pre`.

## Forges

A forge is what opens and looks up pull requests. Two ship:

- **`github`**, with the [GitHub CLI](https://cli.github.com) (`gh`)
- **`gitlab`**, with the [GitLab CLI](https://gitlab.com/gitlab-org/cli) (`glab`) and `jq`. It
  calls them merge requests; git-workflow's messages keep saying pull requests

Unless `workflow.forge` names one, it's `gitlab` when the upstream remote's URL says gitlab,
and `github` otherwise. For a GitHub Enterprise host, set `workflow.forge github`, so release
runs link to its Actions.

A forge is a Bash file of functions, `share/forges/<name>.sh` or
`~/.config/git-workflow/forges/<name>.sh`, picked with `workflow.forge <name>`.
[`share/forges/github.sh`](../share/forges/github.sh) describes the six it needs and the one
it may have:

| Function                                                  | Does                                                              |
| --------------------------------------------------------- | ----------------------------------------------------------------- |
| `forge_name`                                              | what to call it in messages                                       |
| `forge_require`                                           | fail, saying what to install, if it can't work here               |
| `forge_pr_find <branch> <remote>`                         | `<OPEN\|MERGED\|CLOSED> <url>` of the newest pull request from it |
| `forge_pr_merge_commit <branch> <remote>`                 | the commit that merged it (merge, squash or rebase)               |
| `forge_pr_head <branch> <remote>`                         | the head commit it was merged at                                  |
| `forge_pr_create <base> <branch> <remote> <title> <body>` | open one; an empty title fills it from the commits                |
| `forge_ci_hint` (optional)                                | where to watch a release run: `<url>  (or: <command>)`            |

## Guardrails

The warnings below become hard stops when `workflow.strict=true`:

- committing or pushing directly on a protected branch (`main`, `devBranch`, extras)
- release/hotfix names that aren't `vX.Y.Z`, or aren't newer than the latest release
- opening a second branch of a `single` type (git flow's releases) while one is open
- cutting a prerelease from a branch that isn't a release/hotfix branch, or with a tag
  whose version doesn't match the branch
- tagging with uncommitted changes, with commits the remote branch doesn't have, or with a
  `VERSION` file that doesn't match the tag
- finishing a release with commits after its last prerelease, or releasing with no
  prerelease at all

The following always stop: reusing an existing tag, prereleasing a version that already
shipped, finishing or deleting a protected branch, force-pushing a protected branch, pushing a
branch that only takes pull requests, tagging a branch that is behind its remote, tagging local
commits `main` doesn't have, releasing a commit that isn't on `main`, tagging the tip of a
squash-merged release (its tested commit isn't on `main`), deleting a branch with unmerged
commits (without `-f`), and finishing (or deleting the current branch) with uncommitted changes.

`git b pre -n` reports violations as warnings and never stops, so a dry run always shows
what would happen.
