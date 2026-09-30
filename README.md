# git-workflow

[![ci](https://github.com/joshua-hvmn/git-workflow/actions/workflows/ci.yml/badge.svg)](https://github.com/joshua-hvmn/git-workflow/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/joshua-hvmn/git-workflow?include_prereleases&sort=semver)](https://github.com/joshua-hvmn/git-workflow/releases)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Git subcommands that make a branching model the default path: **git flow** (`main` + `next`)
or **trunk / GitHub flow** (`main` only), with SemVer releases, **prerelease tags you can
test in CI before anything reaches `main`**, and guardrails that warn you (or stop you, in
strict mode) when you step outside the flow.

Plain Bash plus `git`. No config file to parse: settings live in `git config`.

```
next ──●────●──────────────────●───────  ← topic branches merge here
        \                     / (back-merge)
release/v1.2.0 ──●──●────●───┘
                 │  │    │
            rc.1 ┘  rc.2 ┘   ← git b pre: tag + push → CI builds a GitHub *prerelease*
                          \
main ──────────────────────●── v1.2.0   ← git b finish: merge, tag, push atomically
```

## Requirements

- Bash 3.2 or newer (macOS's `/bin/bash` works)
- Git 2.30 or newer (`--force-if-includes`)
- Optional: [GitHub CLI](https://cli.github.com) (`gh`), for `workflow.finishTopic=pr`

## Install

Git runs any `git-<name>` executable on your `PATH` as `git <name>`. That's how tools like
`git-lfs` plug in, and it's why these are separate commands instead of one entrypoint.

**From a release** (what a distro package does):

```sh
version=vX.Y.Z
project=git-workflow
username=joshua-hvmn
repo=$username/$project
fingerprint=4474376DA30B98D6FC34D217348CC5A7E89CC1CD
base=https://github.com/$repo/releases/download/$version
package=$project-$version
tarball=$package.tar.gz
signature=$tarball.sig
curl -LO "$base/$tarball" -LO "$base/$signature"

# GPG: Fetch the key and verify, you can skip this if you have gh, use the command below this block.
gpg --keyserver keyserver.ubuntu.com --recv-keys "$fingerprint"
gpg --verify "$signature" "$tarball"
```

_Alternatively, if you have gh and are logged in, you can run:_ `gh attestation verify "$tarball" --repo $repo`.

**Signing key**: `1CEA A8B4 D3B8 749E B348  9943 AEA6 4E97 7A5B 316A`
**Master fingerprint / identity**: `4474 376D A30B 98D6 FC34  D217 348C C5A7 E89C C1CD`
The tarball signing key for this repository is a subkey of my master key, so gpg's "using EDDSA key" line
shows the signing key, not the master fingerprint that is actually used to verify the tarball. The reason
this architecture exists is so I can revoke the signing key for this repository (only) if it is compromised.

```sh
tar xzf "$tarball" && cd "$package" # extract
make check                          # optional: run the test suite (needs bats-core)
sudo make install                   # into /usr/local
```

Or, locally: `make install PREFIX=~/.local`

**From a clone, for hacking on it:**

```sh
git clone https://github.com/joshua-hvmn/git-workflow.git && cd git-workflow
make link                 # symlinks the commands into ~/.local/bin; edits take effect immediately
make unlink               # undo
```

**Aliases** (`git s`, `git lg`, ...) are opt-in, because they edit your `~/.gitconfig`:

```sh
make aliases              # include alias-core/git-workflow-aliases from this checkout
git config --global --add include.path /usr/local/share/git-workflow/git-workflow-aliases   # after make install
```

Then `git b version` shows what's installed, and `git b --help` (or `man git-workflow`) the manual.

`make uninstall` (with the same `PREFIX`) removes an install. `make help` lists every target.

## Configuration

All settings are optional. Set them globally or per repository:

| Key                        | Default    | Meaning                                                                        |
| -------------------------- | ---------- | ------------------------------------------------------------------------------ |
| `workflow.mainBranch`      | `main`     | production branch; stable tags live here                                       |
| `workflow.devBranch`       | `next`     | integration branch. **Set it equal to `mainBranch` for trunk / GitHub flow**   |
| `workflow.remote`          | `origin`   | remote to sync with                                                            |
| `workflow.releasePrefix`   | `release/` | release branch prefix                                                          |
| `workflow.hotfixPrefix`    | `hotfix/`  | hotfix branch prefix                                                           |
| `workflow.prereleaseLabel` | `rc`       | default label for `git b pre`                                                  |
| `workflow.strict`          | `false`    | `true`: flow violations abort. `false`: warn and ask                           |
| `workflow.protected`       | —          | extra protected branches (multi-valued, `git config --add`)                    |
| `workflow.finishTopic`     | `merge`    | `pr`: finishing a topic opens a pull request (`gh`) instead of merging locally |
| `workflow.versionFile`     | `VERSION`  | must match the version `pre`/`finish` tag, when it exists. `""` disables       |

```sh
git config --global workflow.devBranch next     # everywhere
git config workflow.devBranch main              # this repo uses GitHub flow
git config workflow.finishTopic pr              # this repo's dev branch requires reviews
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
- tagging with uncommitted changes, with commits the remote branch doesn't have, or with a
  `VERSION` file that doesn't match the tag

The following always stop: reusing an existing tag, prereleasing a version that already
shipped, finishing or deleting a protected branch, force-pushing a protected branch, tagging
a branch that is behind its remote, deleting a branch with unmerged commits (without `-f`),
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
| `git b delete [branch] [-y] [-f]`             | delete locally and on the remote                                      |
| `git b config` / `git b help`                 | settings / usage                                                      |
| `git b version`                               | installed version (from `VERSION`)                                    |

### start

- **topic**: branch from `devBranch`
- **release**: `release/vX.Y.Z` from `devBranch` (version validated against existing tags)
- **hotfix**: `hotfix/vX.Y.Z` from `mainBranch`

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
(after asking), refusesif the branch is behind its remote, and prints the Actions URL to
watch the run.

Delete a bad prerelease with `gh release delete v1.2.0-rc.1 --cleanup-tag`.

### finish

- **topic**: `--no-ff` merge into `devBranch`, push, delete the branch. With
  `workflow.finishTopic=pr` it pushes the branch and opens a pull request instead (or shows
  the one that's already open). Use that when `devBranch`, `main` in trunk mode, requires
  reviews: a direct push would be rejected
- **release / hotfix**: sync the branch, `--no-ff` merge into `mainBranch`, annotated tag
  `vX.Y.Z`, back-merge `mainBranch` into `devBranch` (skipped in trunk mode), then
  `git push --atomic` of the branches **and only that tag**. Lists the prereleases that were
  cut, and flags when there were none.

`--atomic` means the remote gets everything or nothing. Pushing one explicit tag, not
`--tags`, keeps stray local tags off the remote, and GitHub skips workflow runs when more
than three tags arrive in a single push.

Nothing is pushed until every local step has succeeded, so every failure can be undone. If a
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
aren't merged into main or dev needs `-f`. Protected branches are never deleted.

## Other commands

| Command                     | Description                                                                              |
| --------------------------- | ---------------------------------------------------------------------------------------- |
| `git c [--amend] [message]` | commit; offers `git add -A` if nothing is staged. `--amend` alone keeps the message      |
| `git qc [p] [message]`      | protected-branch check, commit, rebase onto the remote branch, optionally push (`p`)     |
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

`alias-core/git-workflow-aliases` is a git config file (`make aliases` includes it):
`git s`, `git st`, `git lg`, `git graph`, `git aa`, `git au`, `git fprune`.

## CI pairing

Designed to feed a tag-triggered release workflow. This repo releases itself with one,
[`.github/workflows/release.yml`](.github/workflows/release.yml); copy it and change the build step:

- tags containing `-` publish as GitHub prereleases from any branch
- plain `vX.Y.Z` tags are rejected unless the commit is on `main`
- the tag's version must match the `VERSION` file, so bump it on the release branch before
  `git b pre` (`pre` and `finish` check this locally too, before anything is public)
- release notes come from the matching `## vX.Y.Z` section of `CHANGELOG.md`

## Packaging

Everything a package needs goes through standard `make` variables:

```sh
make check                                  # test suite (bats-core)
make PREFIX=/usr DESTDIR="$pkgdir" install  # stage the install for the package
```

| Path (`PREFIX=/usr`)                   | Contents                                    |
| -------------------------------------- | ------------------------------------------- |
| `/usr/bin/git-*`                       | the commands                                |
| `/usr/lib/git-workflow/`               | sourced libraries and `VERSION`             |
| `/usr/share/man/man1/git-*.1`, `man7/` | man pages (`git b --help` opens `git-b(1)`) |
| `/usr/share/git-workflow/`             | the alias file                              |
| `/usr/share/doc/git-workflow/`         | README, CHANGELOG, LICENSE                  |

`BINDIR`, `LIBDIR`, `DATADIR`, `DOCDIR` and `MANDIR` can be overridden individually.
`make install` never touches `$HOME` or `~/.gitconfig`. Release tarballs include the tests.
[`packaging/arch/PKGBUILD`](packaging/arch/PKGBUILD) is a template for an AUR package.

The publish job runs in a `release` environment, so a copy of the workflow needs one
(Settings → Environments), with:

- a required reviewer (every release waits for approval) and a deployment tag rule `v*`
- secrets `GPG_PRIVATE_KEY` (an armored signing subkey export) and `GPG_PASSPHRASE`
- variable `GPG_FINGERPRINT` (that subkey's fingerprint), with the primary key published on
  keyserver.ubuntu.com

Before signing, it fetches the published key, so extending the subkey's expiry only needs
`gpg --send-keys`, not a new secret. It fails if the published key can't verify the
signature, and warns 60 days before the key expires.

## Development

```sh
make link           # run your checkout as the installed commands
make lint           # shellcheck (+ mandoc for the man pages, if installed)
make test           # bats suite (needs bats-core: pacman -S bash-bats / apt install bats / brew install bats-core)
make installcheck   # install into a temp dir and run the suite against that copy
```

Tests run each command against a throwaway bare remote and clone, with your global git config
isolated. `tests/regressions.bats` has one test per fixed bug, grouped by release;
`tests/flows.bats` covers the full flows and guardrails. CI runs lint, the suite, and
`installcheck` on Linux and macOS with its stock Bash 3.2, on every push to a flow branch
and on pull requests.

The publish job runs in a `release` environment, so a copy of the workflow needs one
(Settings → Environments), with:

- a required reviewer (every release waits for approval) and a deployment tag rule `v*`
- secrets `GPG_PRIVATE_KEY` (an armored signing subkey export) and `GPG_PASSPHRASE`
- variable `GPG_FINGERPRINT` (that subkey's fingerprint), with the primary key published on
  keyserver.ubuntu.com

Before signing, it fetches the published key, so extending the subkey's expiry only needs
`gpg --send-keys`, not a new secret. It fails if the published key can't verify the
signature, and warns 60 days before the key expires.
