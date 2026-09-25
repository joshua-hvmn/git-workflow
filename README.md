# git-workflow

Git subcommands that make a branching model the default path: **git flow** (`main` + `next`)
or **trunk / GitHub flow** (`main` only), with SemVer releases, **prerelease tags you can
test in CI before anything reaches `main`**, and guardrails that warn you (or stop you, in
strict mode) when you step outside the flow.

Plain Bash plus `git`. No dependencies and no config file to parse. Settings live in `git config`.

```
next ──●────●──────────────────●───────  ← topic branches merge here
        \                     / (back-merge)
release/v1.2.0 ──●──●────●───┘
                 │  │    │
            rc.1 ┘  rc.2 ┘   ← git b pre: tag + push → CI builds a GitHub *prerelease*
                          \
main ──────────────────────●── v1.2.0   ← git b finish: merge, tag, push atomically
```

## Install

```sh
git clone <repo-url> git-workflow && cd git-workflow
make install              # symlinks git-* into ~/.local/bin, includes the aliases in ~/.gitconfig
make install PREFIX=/usr/local
make uninstall
git b version             # check what's installed
```

Git runs any `git-<name>` executable on your `PATH` as `git <name>`. That is how tools like
`git-lfs` and `git-flow` plug in, and it's why these are separate commands instead of a single
entrypoint. The scripts find their `lib/` by resolving their own symlink, so the repo can live anywhere.

## Configuration

All settings are optional. Set them globally or per repository:

| Key                        | Default    | Meaning                                                                      |
| -------------------------- | ---------- | ---------------------------------------------------------------------------- |
| `workflow.mainBranch`      | `main`     | production branch; stable tags live here                                     |
| `workflow.devBranch`       | `next`     | integration branch. **Set it equal to `mainBranch` for trunk / GitHub flow** |
| `workflow.remote`          | `origin`   | remote to sync with                                                          |
| `workflow.releasePrefix`   | `release/` | release branch prefix                                                        |
| `workflow.hotfixPrefix`    | `hotfix/`  | hotfix branch prefix                                                         |
| `workflow.prereleaseLabel` | `rc`       | default label for `git b pre`                                                |
| `workflow.strict`          | `false`    | `true`: flow violations abort. `false`: warn and ask                         |
| `workflow.protected`       | —          | extra protected branches (multi-valued, `git config --add`)                  |

```sh
git config --global workflow.devBranch next     # everywhere
git config workflow.devBranch main              # this repo uses GitHub flow
git config workflow.strict true                 # this repo: no exceptions
git -c workflow.strict=true b finish            # one-off
git b config                                    # show effective settings
```

### Guardrails

The warnings below become hard stops when `workflow.strict=true`:

- committing or pushing directly on a protected branch (`main`, `devBranch`, extras)
- release/hotfix names that aren't `vX.Y.Z`, or aren't newer than the latest release
- opening a second release branch while one is open (git flow allows one at a time)
- cutting a prerelease from a branch that isn't a release/hotfix branch, or with a tag
  whose version doesn't match the branch
- tagging with uncommitted changes, or with commits the remote branch doesn't have

The following always stop: reusing an existing tag, prereleasing a version that already
shipped, finishing or deleting a protected branch, tagging a branch that is behind its remote,
and finishing (or deleting the current branch) with uncommitted changes.

`git b pre -n` reports violations as warnings and never stops, so a dry run always shows
what would happen.

## `git b`: branches and releases

| Command                                       | Description                                                           |
| --------------------------------------------- | --------------------------------------------------------------------- |
| `git b`                                       | `git branch` (anything unrecognised passes through, e.g. `git b -vv`) |
| `git b start <topic\|release\|hotfix> [name]` | start a branch from the right base and push it                        |
| `git b pre [label\|tag] [-n] [-l]`            | tag the release branch as a prerelease and push the tag               |
| `git b finish [branch]`                       | merge per the flow, tag releases/hotfixes, push, delete the branch    |
| `git b delete [branch] [-y]`                  | delete locally and on the remote                                      |
| `git b config` / `git b help`                 | settings / usage                                                      |
| `git b version`                               | installed version (from `VERSION`)                                    |

### start

- **topic**: branch from `devBranch`
- **release**: `release/vX.Y.Z` from `devBranch` (version validated against existing tags)
- **hotfix**: `hotfix/vX.Y.Z` from `mainBranch`

Aborts if the tree has untracked files (autostash can't carry them). Tracked edits come along
to the new branch, the same as `git switch -c`. On a fresh clone, a missing local `main` or
`devBranch` is created from the remote automatically.

### prerelease: test the release pipeline before `main`

```sh
git b start release v1.2.0
# ...commit fixes...
git b pre              # tags v1.2.0-rc.1 and pushes it → CI publishes a GitHub prerelease
# ...download the tarball, test it, fix things...
git b pre              # v1.2.0-rc.2 (numbering continues from existing local + remote tags)
git b pre beta         # v1.2.0-beta.1
git b pre v1.2.0-rc.9  # exact tag
git b pre -n           # dry run: show what would be tagged (warns, never prompts)
git b pre -l           # list prereleases for this version
git b finish           # v1.2.0 on main
```

Before tagging it fetches tags, pushes any unpushed branch commits (after asking), refuses
if the branch is behind its remote, and prints the Actions URL to watch the run.

Delete a bad prerelease with `gh release delete v1.2.0-rc.1 --cleanup-tag`.

### finish

- **topic**: `--no-ff` merge into `devBranch`, push, delete the branch.
- **release / hotfix**: sync the branch, `--no-ff` merge into `mainBranch`, annotated tag
  `vX.Y.Z`, back-merge `mainBranch` into `devBranch` (skipped in trunk mode), then
  `git push --atomic` of the branches **and only that tag**. Lists the prereleases that were
  cut, and flags when there were none.

Refuses to start with uncommitted changes, since it switches branches and git would carry
them onto `devBranch`.

`--atomic` means the remote gets everything or nothing. Pushing one explicit tag, not
`--tags`, keeps stray local tags off the remote, and GitHub skips workflow runs when more
than three tags arrive in a single push.

If the push is rejected (a hook, a race, a dropped connection), nothing was published but the
merge and tag exist locally. finish prints the exact command to retry the push, and offers to
roll back instead: it deletes the tag, resets `mainBranch`/`devBranch` to where they were, and
puts you back on the release branch so you can fix the cause and run `git b finish` again.

### delete

Deletes locally and remotely, asking first unless you pass `-y` with an explicit branch
name. Won't delete protected branches. If you abort, you're switched back to the branch
you were on.

## Other commands

| Command                     | Description                                                                          |
| --------------------------- | ------------------------------------------------------------------------------------ |
| `git c [--amend] [message]` | commit; offers `git add -A` if nothing is staged. `--amend` alone keeps the message  |
| `git qc [p] [message]`      | protected-branch check, commit, rebase onto the remote branch, optionally push (`p`) |
| `git ps [force]`            | sync with the remote, then `push -u`; `force` → `--force-with-lease`                 |
| `git sync [branch]`         | `fetch --all --prune --tags`, then bring the branch up to date (see below)           |
| `git rb-pull [branch]`      | switch to a branch and bring it up to date with the remote                           |
| `git sq [base]`             | interactive `rebase --keep-base` to squash the branch's own commits                  |

Messages don't need quotes: `git c fix the bug` commits "fix the bug".

"Up to date" means: protected branches (`main`, `devBranch`) are fast-forwarded only and the
command stops if they've diverged, so unpushed merge commits are never flattened. Other
branches are rebased onto their remote with `--autostash`.

`git qc` commits _before_ syncing. Syncing first would autostash, and git restores an
autostash without the staged/unstaged split, so a partial `git add` would be lost.

`git sq` defaults to `<remote>/<devBranch>` and uses `--keep-base`, so it only rewrites your
commits and never moves the branch onto a newer base (that's what `git sync` is for).

## Aliases

`alias-core/git-workflow-aliases` is a git config file (`make install` includes it):
`git s`, `git st`, `git lg`, `git graph`, `git aa`, `git au`, `git fprune`.

## CI pairing

Designed to feed a tag-triggered release workflow. This repo releases itself with one,
[`.github/workflows/release.yml`](.github/workflows/release.yml); copy it and change the build step:

- tags containing `-` publish as GitHub prereleases from any branch
- plain `vX.Y.Z` tags are rejected unless the commit is on `main`
- the tag's version must match the `VERSION` file, so bump it on the release branch before `git b pre`

## Development

```sh
make lint    # shellcheck
make test    # bats suite (needs bats-core: apt install bats / brew install bats-core)
```

Tests run each command against a throwaway bare remote and clone, with your global git config
isolated. `tests/regressions.bats` has one test per fixed bug; `tests/flows.bats` covers the
full flows and guardrails. CI runs both on every push to a flow branch and on pull requests.
