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
shipped, finishing or deleting a protected branch, and tagging a branch that is behind its remote.

## `git b`: branches and releases

| Command                                       | Description                                                           |
| --------------------------------------------- | --------------------------------------------------------------------- |
| `git b`                                       | `git branch` (anything unrecognised passes through, e.g. `git b -vv`) |
| `git b start <topic\|release\|hotfix> [name]` | start a branch from the right base and push it                        |
| `git b pre [label\|tag] [-n] [-l]`            | tag the release branch as a prerelease and push the tag               |
| `git b finish [branch]`                       | merge per the flow, tag releases/hotfixes, push, delete the branch    |
| `git b delete [branch] [-y]`                  | delete locally and on the remote                                      |
| `git b config` / `git b help`                 | settings / usage                                                      |

### start

- **topic**: branch from `devBranch`
- **release**: `release/vX.Y.Z` from `devBranch` (version validated against existing tags)
- **hotfix**: `hotfix/vX.Y.Z` from `mainBranch`

Aborts if the tree has untracked files (autostash can't carry them).

### prerelease: test the release pipeline before `main`

```sh
git b start release v1.2.0
# ...commit fixes...
git b pre              # tags v1.2.0-rc.1 and pushes it → CI publishes a GitHub prerelease
# ...download the tarball, test it, fix things...
git b pre              # v1.2.0-rc.2 (numbering continues from existing local + remote tags)
git b pre beta         # v1.2.0-beta.1
git b pre v1.2.0-rc.9  # exact tag
git b pre -n           # dry run: show what would be tagged
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

`--atomic` means the remote gets everything or nothing. Pushing one explicit tag, not
`--tags`, keeps stray local tags off the remote, and GitHub skips workflow runs when more
than three tags arrive in a single push.

### delete

Deletes locally and remotely, asking first unless you pass `-y` with an explicit branch
name. Won't delete protected branches. If you abort, you're switched back to the branch
you were on.

## Other commands

| Command                     | Description                                                                     |
| --------------------------- | ------------------------------------------------------------------------------- |
| `git c [--amend] [message]` | commit; offers `git add -A` if nothing is staged, prompts for a message         |
| `git qc [p] [message]`      | protected-branch check, sync with the remote, commit, and optionally push (`p`) |
| `git ps [force]`            | `push -u` to the remote (after syncing); `force` → `--force-with-lease`         |
| `git sync [branch]`         | `fetch --all --prune`, then `pull --rebase --autostash`                         |
| `git rb-pull [branch]`      | `pull --rebase --autostash` for a branch                                        |
| `git sq [base]`             | interactive rebase onto `devBranch` to squash                                   |

## Aliases

`alias-core/git-workflow-aliases` is a git config file (`make install` includes it):
`git s`, `git st`, `git lg`, `git graph`, `git aa`, `git au`, `git fprune`.

## CI pairing

Designed to feed a tag-triggered release workflow (see wg-vpn's `.github/workflows/release.yml`):
tags containing `-` publish as GitHub prereleases from any branch, and plain `vX.Y.Z` tags
are rejected unless the commit is on `main`.
