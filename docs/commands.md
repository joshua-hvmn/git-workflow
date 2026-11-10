# Commands

What each command does, in detail. `git workflow help <command>` opens its manual page.

## `git b`: branches and releases

`git b` is `git workflow branch`

| Command                                          | Description                                                                 |
| ------------------------------------------------ | --------------------------------------------------------------------------- |
| `git b`                                          | `git branch` (options pass through, e.g. `git b -vv`)                       |
| `git b start <type> [name\|major\|minor\|patch]` | start a branch of one of the flow's types, from the right base, and push it |
| `git b pre [label\|vX.Y.Z\|tag] [-n] [-l]`       | tag a release/hotfix branch (or `main`, in GitHub flow) as a prerelease     |
| `git b release [vX.Y.Z] [-n]`                    | GitHub flow: tag the newest prerelease's commit as the release              |
| `git b finish [branch]`                          | open a pull request, or merge per the flow; tag releases/hotfixes; clean up |
| `git b delete [branch] [-y] [-f]`                | delete locally and on the remote                                            |
| `git b status [--no-fetch]`                      | where you are in the flow, what to run next, and what's left to do          |
| `git b config` / `git b help`                    | the flow and settings / usage                                               |
| `git workflow version`                           | installed version (from `VERSION`)                                          |

`start`, `pre`, `release` and `finish` take `-y`: they answer their own questions with yes,
printing each one, so they can run from a script. A flow warning isn't one of those questions:
it still asks, and stops without a terminal or with `workflow.strict`. `-y` means "I meant
this", not "skip the guardrails".

Only options go to `git branch`. Any other word is refused, so a typo like `git b finsh` is an
error instead of a new branch named `finsh`. Use `git branch <name>` for a branch outside the flow.

### start

`git b start <type>` starts a branch of one of the flow's types (`git b config` lists them),
from where the type says. In the shipped flows:

- **topic**: from `devBranch` (`main` in GitHub flow)
- **release** (git flow): `release/vX.Y.Z` from `devBranch` (version validated against existing tags)
- **hotfix**: `hotfix/vX.Y.Z` from `mainBranch` (in GitHub flow, from the latest release tag:
  `main` already has unreleased work)

Tracked edits come along to the new branch, the same as `git switch -c`. A name that already
exists locally or on the remote is refused. On a fresh clone, a missing local `main` or
`devBranch` is created from the remote automatically.

For a release or hotfix, `major`, `minor` or `patch` in place of the version starts the next
one after the latest release, and a version typed without its `v` gets one:

```console
$ git b start release minor
Next minor version: v1.4.0 (after v1.3.2).
Starting release branch 'release/v1.4.0' from 'next'...
VERSION says 'v1.3.2'. Set it to v1.4.0 and commit? [Y/n]: y
Committed VERSION at v1.4.0.
```

The version file can be `package.json`, `Cargo.toml` or `pyproject.toml`
([versions](configuration.md#versions)), and the tags can have another prefix, or none.

### prerelease: test the release pipeline before `main`

```sh
git b start release v1.2.0   # offers to set VERSION to v1.2.0 and commit it
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

Before tagging it fetches tags, checks the `VERSION` file, pushes any unpushed branch commits
(after asking), refuses if the branch is behind its remote, and prints the Actions URL to
watch the run.

Delete a bad prerelease with `gh release delete v1.2.0-rc.1 --cleanup-tag`.

### finish

With pull requests (the default):

- **topic**: push the branch and open a pull request (or show the one that's already open).
  Run `finish` again once it's merged, however it was merged (merge commit, squash or
  rebase), and it deletes the branch and brings your dev branch up to date
- **release / hotfix**: the same, into `mainBranch`. Once it's merged, `finish` again tags
  `vX.Y.Z` and pushes only the tag, then opens the back-merge pull request into `devBranch`
  (git flow). Tagging the merge works however it was merged; tagging the tested tip (GitHub
  flow's hotfixes) needs a merge commit, and `finish` refuses a squashed one

Merging locally (`integrate = merge`):

- **topic**: `--no-ff` merge into `devBranch`, push, delete the branch
- **release / hotfix**: sync the branch, `--no-ff` merge into `mainBranch`, annotated tag
  `vX.Y.Z` (on the merge, or the tested tip), back-merge `mainBranch` into `devBranch`, then
  `git push --atomic` of the branches **and only that tag**

Either way it lists the prereleases that were cut, and flags when there were none, or when
the branch has commits after the last one.

`--atomic` means the remote gets everything or nothing. Pushing one explicit tag, not
`--tags`, keeps stray local tags off the remote, and GitHub skips workflow runs when more
than three tags arrive in a single push.

When merging locally, nothing is pushed until every local step has succeeded, so every
failure can be undone. If a
merge conflicts, `devBranch` has diverged, or the push is rejected, finish aborts the merge,
deletes the tag it made, resets `mainBranch`/`devBranch` to where they were, and puts you back
on the branch you were finishing: fix the cause, then run `git b finish` again. For a rejected
release push or a back-merge conflict it asks first, and otherwise prints the exact command to
complete the release by hand.

finish refuses to start with uncommitted changes, since it switches branches and git would
carry them onto `devBranch`.

### delete

Deletes locally and remotely, asking first unless you pass `-y` with an explicit branch
name. It checks everything before switching or deleting anything: a branch with commits that
aren't merged into main or dev needs `-f`. A branch whose pull request was squash- or
rebase-merged counts as merged. Protected branches are never deleted.

### status

`git b status` says where you are in the flow and what to run next, which branches are open,
and what's been left half done:

```console
$ git b status
gitflow flow: main and next; latest release v1.3.2.

On release/v1.4.0, the release branch for v1.4.0, into main.
  3 commits of its own; all pushed.
  Prereleases: v1.4.0-rc.1 (1 commit after v1.4.0-rc.1).
  Next: git b pre to test what changed, or git b finish (opens a pull request into main).

Open branches:
  topic     fix-typo
  release   release/v1.4.0

Left to do:
  fix-typo is merged into origin/next: git b delete fix-typo
```

With pull requests, a release is tagged when `finish` runs again after its pull request
merged. A release branch that was merged but never tagged shows up under "Left to do", and so
does a merged branch that's still around, and (in GitHub flow) a prerelease of `main` that was
never released. `status` fetches first, unless `--no-fetch`, and asks the forge only about the
current branch, and only when git can't tell it was merged.

## Other commands

Each is an alias for a `git workflow` command: `c` for `commit`, `qc` for `quick-commit`, `ps`
for `push`, `rb-pull` for `pull` and `sq` for `squash`; `sync` keeps its name.

| Command                     | Description                                                                              |
| --------------------------- | ---------------------------------------------------------------------------------------- |
| `git c [--amend] [message]` | commit; offers `git add -A` if nothing is staged. `--amend` alone keeps the message      |
| `git qc [p] [message]`      | protected-branch check, commit, sync with the remote branch, optionally push (`p`)       |
| `git ps [force]`            | sync with the remote, then `push -u`; `force` → `--force-with-lease --force-if-includes` |
| `git sync [branch]`         | `fetch --all --prune --tags`, then bring the branch up to date (see below)               |
| `git rb-pull [branch]`      | switch to a branch and bring it up to date with the remote                               |
| `git sq [base]`             | interactive `rebase --keep-base` to squash the branch's own commits                      |

**Messages are plain words**: `git c fix the bug` commits "fix the bug". Two things to know:

- Arguments starting with `-` are refused, because they're almost always `git commit` flags
  typed from habit (`git c -m fix` would otherwise commit "-m fix"). Use `--` for a message
  that really starts with a dash: `git c -- -v flag removed`.
- Your shell still reads the words first. Quote a message that contains `#`, `'`, `*`, `?`
  or `!`: `git c "fix #12"`.

`git c` and `git qc` both warn before committing on a protected branch. Only `p`, `-p` or
`--push` put `git qc` in push mode; the word "push" starts the message like any other.

"Up to date" means: protected branches (`main`, `devBranch`) are fast-forwarded only and the
command stops if they've diverged, so unpushed merge commits are never flattened. Other
branches are rebased onto their remote with `--autostash`.

`git qc` commits _before_ syncing. Syncing first would autostash, and git restores an
autostash without the staged/unstaged split, so a partial `git add` would be lost.

`git sq` squashes against `<remote>/<devBranch>` (`<remote>/<mainBranch>` for hotfixes) and
uses `--keep-base`, so it only rewrites your commits and never moves the branch onto a newer
base (that's what `git sync` is for). If those commits were already pushed, it tells you to
publish with `git ps force`, and plain `git ps` refuses a rewritten branch rather than
replaying the old commits on top.

`git ps force` adds `--force-if-includes` to the lease: the remote is only overwritten if its
tip is something your branch has seen, so a background fetch (editors do this) can't make it
overwrite someone else's commits. Protected branches are never force-pushed.

## Aliases

| Command                                | Does                                                                       |
| -------------------------------------- | -------------------------------------------------------------------------- |
| `git workflow aliases [list]`          | the aliases that run git-workflow commands, and where each set is          |
| `git workflow aliases install [<set>]` | copy `commands` (or the sets you name) to `~/.config/...` and include them |
| `git workflow aliases reset <set>`     | restore a set's default (yours is kept as `<set>.bak`)                     |
| `git workflow aliases remove [<set>]`  | stop including the sets, all of them by default (your copies stay)         |

The sets are git config files, `commands` and `extras`:

```ini
[alias]
    b = workflow branch          # commands
    c = workflow commit
    qc = workflow quick-commit
    ps = workflow push
    sq = workflow squash
    sync = workflow sync
    rb-pull = workflow pull
    wf = workflow                # anything else: git wf help, git wf version
```

`extras` has `git lg`, `git graph`, `git s`, `git st`, `git aa`, `git au` and `git fprune`.

`install` never overwrites your copy, and it warns when a `git-<name>` program on your `PATH`
would run instead of an alias (git prefers programs to aliases). `git b --help` opens
`git-workflow(1)`, because git opens the page for an alias's first word; `git workflow help
branch` opens the command's own page.
