# git-workflow

[![ci](https://github.com/joshua-hvmn/git-workflow/actions/workflows/ci.yml/badge.svg)](https://github.com/joshua-hvmn/git-workflow/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/joshua-hvmn/git-workflow?include_prereleases&sort=semver)](https://github.com/joshua-hvmn/git-workflow/releases)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Git subcommands that make a branching model the default path: **git flow** (`main` + `next`),
**GitHub flow** (`main` only, releases are tags), or [your own](#writing-a-flow), with SemVer
releases, **prerelease tags you can test in CI before anything reaches `main`**, and
guardrails that warn you (or stop you, in strict mode) when you step outside the flow.

`finish` opens a pull request unless you say otherwise, so it's safe on repositories you don't
own, forks included. A repository can commit its flow in a `.gitworkflow` file, and every
contributor's `git b` follows it.

Plain Bash plus `git`. Settings live in `git config`, or in that `.gitworkflow` file.

## Example, with most git output omitted:

```console
$ git b start release v1.3.0
Starting release branch 'release/v1.3.0' from 'next'...
Switched to a new branch 'release/v1.3.0'
$ echo v1.3.0 >VERSION && git aa && git c bump version to v1.3.0
[release/v1.3.0 de4936e] bump version to v1.3.0
$ git b pre
Push 1 local commit(s) to 'origin/release/v1.3.0' first? [Y/n]: y
Create prerelease tag 'v1.3.0-rc.1' at de4936e and push it (triggers the release workflow)? [y/N]: y
Pushed prerelease 'v1.3.0-rc.1'.
Watch the release run: https://github.com/you/app/actions  (or: gh run watch)
$ git b finish
Prereleases for v1.3.0: v1.3.0-rc.1
Merge 'release/v1.3.0' into main and next, tag v1.3.0, and push? [y/N]: y
   920eaa0..ec7014e  main -> main
   920eaa0..ec7014e  next -> next
 * [new tag]         v1.3.0 -> v1.3.0
Released 'v1.3.0'.
Watch the release run: https://github.com/you/app/actions  (or: gh run watch)
Delete 'release/v1.3.0' locally and on 'origin'? [y/N]: y
Branch release/v1.3.0 deleted. You're on next.
$ git c quick fix
Warning: 'main' is a protected branch; you are about to commit directly on it.
Continue anyway? [y/N]: n
Aborted.
```

_A real session, with most of git's own output left out. This repository merges its releases
locally (`workflow.release.integrate merge`); by default, `finish` opens a pull request._

```
next ───●──────────────────────●──  ← topic branches merge here
         \                    /     ← back-merge: main into next
release/v1.3.0 ─●────●───────●
                │    │\     /
             rc.1 rc.2 \   /        ← git b pre: tag + push → CI builds a GitHub prerelease
                        \ /
main ────────────────────●────────  v1.3.0  ← git b finish: merge, tag, push atomically
```

## Install

git-workflow installs one program, `git-workflow`, which git runs as `git workflow` (git runs
any `git-<name>` on your `PATH` as `git <name>`; that's how `git lfs` plugs in too). The short
names, `git b`, `git c` and so on, are aliases you opt into, so git-workflow never takes a name
you already use.

It needs Bash 3.2 or newer (macOS's `/bin/bash` works) and Git 2.30 or newer. `finish` opens
pull requests with the [GitHub CLI](https://cli.github.com) (`gh`); without it, set
`workflow.integrate merge` to merge locally instead.

### From a release

```sh
version=vX.Y.Z    # the release to install
base=https://github.com/joshua-hvmn/git-workflow/releases/download/$version
curl -LO "$base/git-workflow-$version.tar.gz" -LO "$base/git-workflow-$version.tar.gz.sig"
gpg --keyserver keyserver.ubuntu.com --recv-keys 4474376DA30B98D6FC34D217348CC5A7E89CC1CD  # once
gpg --verify "git-workflow-$version.tar.gz.sig" "git-workflow-$version.tar.gz" &&
    tar xzf "git-workflow-$version.tar.gz" && cd "git-workflow-$version"
sudo make install    # into /usr/local; or for just you: make install PREFIX="$HOME/.local"
```

[Verifying a release](#verifying-a-release) explains the key. The tarball includes the tests:
`make check` runs them before you install.

### From a clone, for hacking on it

```sh
git clone https://github.com/joshua-hvmn/git-workflow.git && cd git-workflow
make link                 # symlinks the program into ~/.local/bin; edits take effect immediately
make unlink               # undo
```

### Setting up the aliases

The aliases are opt-in, because they edit your `~/.gitconfig`:

```sh
git workflow aliases install         # or, from the source directory: make aliases
git workflow aliases install extras  # optional: git lg, git s, ... (make aliases SETS=extras)
```

That copies the `commands` alias set (`git b`, `git c`, `git qc`, `git ps`, `git sq`, `git sync`,
`git rb-pull`, `git wf`) into `~/.config/git-workflow/aliases/` and includes it from
`~/.gitconfig` as `~/.config/...`, so a synced `~/.gitconfig` works on every machine. The
`extras` set, general-purpose aliases unrelated to the flow, is opt-in. The copies are yours:
rename or delete aliases, and messages and `git workflow help` use your names. An alias you
already have, in `~/.gitconfig` or a file it includes, keeps working (it's left out of your
copy). The rest of this README uses the default names.

Then `git workflow version` shows what's installed, `git workflow help` lists the commands with
your alias for each, and `man git-workflow` is the manual.

### Tab completion

`make install` puts a bash completion where bash-completion finds it, and git's own completion
loads it the first time you complete a `git workflow` command. It completes the commands,
`git b` subcommands, the flow's branch types and branch names, through your aliases too
(`git b fi<TAB>`).
From a clone, source `completion/git-workflow.bash` from `~/.bashrc`.

### Uninstalling and upgrading

`make uninstall` (with the same `PREFIX`) removes an install; your alias copies stay, and
`make unaliases` stops including them. `make help` lists every target.

**Upgrading from v2.x**: `finish` opens pull requests now. Your settings keep working
(`finishTopic`, `releasePrefix` and `hotfixPrefix` are read under their new names), but unset
`workflow.devBranch` if you set it globally: it's per repository now, and a global one would
make every repository git flow. To merge locally as before, see [Flows](#flows).

**Upgrading from v1.x**: `make install` removes the 1.x `git-*` commands from the same `PREFIX`
(git would run them instead of the new aliases), and `git workflow aliases install` replaces the
1.x alias include, keeping the extras (`git lg`, ...) it had. See the [CHANGELOG](CHANGELOG.md).

## Flows

A flow decides where each kind of branch starts and where `finish` takes it. Two ship:

- **`gitflow`**: `main` holds releases and `next` collects finished work. Topics go into
  `next`; `release/vX.Y.Z` branches go from `next` into `main`, tagged on the merge, and `main`
  is merged back into `next`; `hotfix/vX.Y.Z` branches do the same from `main`.
- **`github`**: everything starts from `main` and goes back into it. A release is a tag:
  [`pre` and `release` on `main`](#releasing-from-main). `hotfix/vX.Y.Z` branches start from the
  latest release (since `main` already has unreleased work) and are tagged on their tested tip.

Unless you pick one with `workflow.flow`, it's guessed: a `next` branch (or `develop`, which
then becomes the dev branch) means `gitflow`, anything else `github`. `git b config` shows the
flow, why, and where every setting came from.

### How `finish` integrates

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

### Settings

Every setting is a `workflow.*` key. These apply to the whole flow:

| Key                        | Default                                | Meaning                                                            |
| -------------------------- | -------------------------------------- | ------------------------------------------------------------------ |
| `workflow.flow`            | guessed (above)                        | `gitflow`, `github`, or a flow of your own                         |
| `workflow.mainBranch`      | the remote's default branch            | production branch; stable tags live here                           |
| `workflow.devBranch`       | the flow's (`next`), else `mainBranch` | integration branch                                                 |
| `workflow.integrate`       | `pr`                                   | `pr`: finish opens a pull request. `merge`: it merges locally      |
| `workflow.releaseFromMain` | the flow's                             | `true`: `pre` and `release` tag `main` directly                    |
| `workflow.remote`          | `origin`                               | where your branches go (your fork, if you use one)                 |
| `workflow.upstream`        | `upstream` if it exists, else `remote` | where main, dev and the tags live; pull requests go here           |
| `workflow.forge`           | `github`                               | what opens pull requests (`github`: the `gh` CLI)                  |
| `workflow.prereleaseLabel` | `rc`                                   | default label for `git b pre`                                      |
| `workflow.strict`          | `false`                                | `true`: flow violations abort. `false`: warn and ask               |
| `workflow.versionFile`     | `VERSION`                              | must match the version being tagged, when it exists. `""` disables |
| `workflow.protected`       | —                                      | extra protected branches (multi-valued, `git config --add`)        |

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

### A repository's `.gitworkflow`

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
own [`.gitworkflow`](.gitworkflow) is an example.

### Writing a flow

A flow is a file of these settings. Put one in `~/.config/git-workflow/flows/<name>` and pick it
with `workflow.flow <name>`; it can define its own branch types. Starting from a shipped flow
([`share/flows/`](share/flows/)) is easiest. This one keeps a single long-lived branch and
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
forge, `share/forges/github.sh`: another host is another file with the same five functions.

### Guardrails

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

## `git b`: branches and releases

`git b` is `git workflow branch`

| Command                                    | Description                                                                 |
| ------------------------------------------ | --------------------------------------------------------------------------- |
| `git b`                                    | `git branch` (options pass through, e.g. `git b -vv`)                       |
| `git b start <type> [name]`                | start a branch of one of the flow's types, from the right base, and push it |
| `git b pre [label\|vX.Y.Z\|tag] [-n] [-l]` | tag a release/hotfix branch (or `main`, in GitHub flow) as a prerelease     |
| `git b release [vX.Y.Z] [-n]`              | GitHub flow: tag the newest prerelease's commit as the release              |
| `git b finish [branch]`                    | open a pull request, or merge per the flow; tag releases/hotfixes; clean up |
| `git b delete [branch] [-y] [-f]`          | delete locally and on the remote                                            |
| `git b config` / `git b help`              | the flow and settings / usage                                               |
| `git workflow version`                     | installed version (from `VERSION`)                                          |

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

### prerelease: test the release pipeline before `main`

```sh
git b start release v1.2.0
# ...bump VERSION to v1.2.0, commit fixes...
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

## GitHub flow, and repositories you don't own

In GitHub flow nothing pushes to `main`, so it works when `main` only accepts pull requests,
and on repositories where you don't decide how things are set up. `git ps` and `git qc p`
refuse to push a branch that only takes pull requests, and say how to move your commits to a
branch.

```sh
git b start topic fix-typo   # from main, pushed as its own branch
git c fix the typo
git b finish                 # pushes it and opens a pull request into main (gh)
# ...review, merge on GitHub...
git b finish                 # merged: deletes the branch and brings main up to date
```

### Releasing from `main`

A release is a tag, so it doesn't need a push to `main`:

```sh
git b pre              # on main: tags v1.2.0-rc.1 (version from VERSION, or: git b pre v1.2.0)
# ...CI publishes the prerelease; test it...
git b release          # tags the commit rc.1 tested as v1.2.0 and pushes only the tag
```

`git b release` tags the newest prerelease's commit, not whatever `main` has reached by then,
so the release is exactly what you tested; it says how many commits `main` has gained since.
With no prerelease it warns that the release is untested (strict mode refuses). `pre` on `main`
fast-forwards it first, and refuses local commits that aren't on the remote `main`.

### Forks

With a remote named `upstream` (or `workflow.upstream`), `main` and the tags come from
upstream, your branches go to `origin` (your fork), and pull requests go to upstream from your
fork's branch:

```sh
gh repo fork owner/project --clone   # origin is your fork, upstream is owner/project
cd project
git b start topic fix-typo           # from upstream/main, pushed to your fork
git b finish                         # pull request into owner/project from <you>:fix-typo
git sync                             # main from upstream
```

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

## CI pairing

Designed to feed a tag-triggered release workflow. This repo releases itself with one,
[`.github/workflows/release.yml`](.github/workflows/release.yml); copy it and change the build step:

- tags containing `-` publish as GitHub prereleases from any branch
- plain `vX.Y.Z` tags are rejected unless the commit is on `main`
- the tag's version must match the `VERSION` file, so bump it on the release branch before
  `git b pre` (`pre` and `finish` check this locally too, before anything is public)
- release notes come from the matching `## vX.Y.Z` section of `CHANGELOG.md`
- the publish job checks the tarball against the hash the build job computed, so a tarball
  that changed in artifact storage is never signed

The publish job runs in a `release` environment, so a copy of the workflow needs one
(Settings → Environments), with:

- a required reviewer (every release waits for approval) and a deployment tag rule `v*`
- secrets `GPG_PRIVATE_KEY` (an armored signing subkey export) and `GPG_PASSPHRASE`
- variable `GPG_FINGERPRINT` (that subkey's fingerprint), with the primary key published on
  keyserver.ubuntu.com

Before signing, it fetches the published key, so extending the subkey's expiry only needs
`gpg --send-keys`, not a new secret. It fails if the published key can't verify the
signature, and warns 60 days before the key expires.

## Verifying a release

Every release tarball is signed, and its build provenance is attested by GitHub.

**Primary key**, the one to trust (confirm it somewhere other than this repository):

```
4474 376D A30B 98D6 FC34  D217 348C C5A7 E89C C1CD
```

**Signing subkey**, used only for this repository's releases:

```
1CEA A8B4 D3B8 749E B348  9943 AEA6 4E97 7A5B 316A
```

gpg's "using EDDSA key" line names the signing subkey. Unless you've certified the key, gpg also
warns that it isn't certified and prints both fingerprints: "Primary key fingerprint" should match
the primary key above, and "Subkey fingerprint" the signing subkey. Each repository has its own
subkey, so a compromised one can be revoked without affecting the primary key or other projects.

With `gh` logged in, you can check the provenance instead:
`gh attestation verify git-workflow-vX.Y.Z.tar.gz --repo joshua-hvmn/git-workflow`.

## Packaging

Everything a package needs goes through standard `make` variables:

```sh
make check                                  # test suite (bats-core)
make PREFIX=/usr DESTDIR="$pkgdir" install  # stage the install for the package
```

| Path (`PREFIX=/usr`)                                  | Contents                                                    |
| ----------------------------------------------------- | ----------------------------------------------------------- |
| `/usr/bin/git-workflow`                               | the program                                                 |
| `/usr/share/git-workflow/`                            | sourced libraries and `VERSION`                             |
| `/usr/share/git-workflow/commands/`                   | one file per command, sourced by the program                |
| `/usr/share/git-workflow/flows/`                      | the flows (`gitflow`, `github`)                             |
| `/usr/share/git-workflow/forges/`                     | what opens pull requests (`github.sh`)                      |
| `/usr/share/git-workflow/aliases/`                    | the default alias sets                                      |
| `/usr/share/man/man1/git-workflow*.1`                 | man pages (`git workflow help <command>` opens a command's) |
| `/usr/share/bash-completion/completions/git-workflow` | bash completion, loaded by git's own                        |
| `/usr/share/doc/git-workflow/`                        | README, CHANGELOG, LICENSE                                  |

`BINDIR`, `DATADIR`, `DOCDIR`, `MANDIR` and `COMPLETIONDIR` can be overridden individually.
`make install` never touches `$HOME` or `~/.gitconfig`, and removes 1.x files from the same
`PREFIX`. Release tarballs include the tests.

[`packaging/`](packaging/) has an AUR `PKGBUILD` and a Homebrew formula built this way, and
how to publish each.

## Development

```sh
make link           # run your checkout as the installed program
make lint           # shellcheck, plus shfmt and mandoc when they're installed
make test           # bats suite (needs bats-core: pacman -S bash-bats / apt install bats / brew install bats-core)
make installcheck   # install into a temp dir and run the suite against that copy
```

Tests run each command against a throwaway bare remote and clone, with your global git config
and `~/.config` isolated and the default aliases installed. `tests/regressions.bats` has one test
per fixed bug, grouped by release; `tests/flows.bats` covers the full flows and guardrails;
`tests/github-flow.bats` pull requests, releasing from `main` and forks (with a stand-in for
`gh`, and a remote whose `main` refuses pushes); `tests/flow-config.bats` flows, settings
layers and `.gitworkflow`; `tests/cli.bats` the program itself, its help and the alias sets. CI runs lint, the suite, and
`installcheck` on Linux and macOS with its stock Bash 3.2, on every push to a flow branch
and on pull requests.
