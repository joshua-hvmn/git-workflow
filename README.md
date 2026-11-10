# git-workflow

[![ci](https://github.com/joshua-hvmn/git-workflow/actions/workflows/ci.yml/badge.svg)](https://github.com/joshua-hvmn/git-workflow/actions/workflows/ci.yml)
[![release](https://img.shields.io/github/v/release/joshua-hvmn/git-workflow?include_prereleases&sort=semver)](https://github.com/joshua-hvmn/git-workflow/releases)
[![license: MIT](https://img.shields.io/badge/license-MIT-blue.svg)](LICENSE)

Git subcommands that make your branching model the default path, and your release exactly
what you tested: prerelease tags your CI builds **before anything reaches `main`**, and a
release tag on the very commit they tested.

- **A flow, as data.** git flow (`main` + `next`), GitHub flow (`main` only, releases are
  tags), or [your own](docs/configuration.md#writing-a-flow), as a file of settings. A
  repository can commit its flow in `.gitworkflow`, and every contributor's `git b` follows it.
- **Prereleases first.** `git b pre` tags `v1.3.0-rc.1` and pushes only the tag, so your
  release workflow publishes a real prerelease from the release branch. `finish` flags commits
  no prerelease tested.
- **Safe on repositories you don't own.** `finish` opens a pull request (GitHub or GitLab),
  from forks too; run it again once it's merged to tag and clean up. Or merge locally, with
  one atomic push, and every step rolled back if anything fails.
- **Guardrails, not gates.** Committing on `main`, a version that isn't newer, a version file
  that doesn't match: warnings by default, stops with `workflow.strict`. `git b status` says
  what's next, and what's been left half done.
- **Versions where your project keeps them.** `VERSION`, `package.json`, `Cargo.toml` or
  `pyproject.toml`; tags `v1.2.3`, `1.2.3` or `pkg-a/v1.2.3`; and `git b start release minor`
  works out the number.

Plain Bash and `git`, nothing to build. Settings live in `git config`, or in that
`.gitworkflow` file.

<!-- Record it with `vhs docs/demo.tape`, then show it here:
![git-workflow: status, start, prerelease, finish](docs/demo.gif)
-->

## Example, with most git output omitted:

```console
$ git b start release minor
Next minor release: v1.3.0 (after v1.2.4).
Starting release branch 'release/v1.3.0' from 'next'...
VERSION says 'v1.2.4'. Set it to v1.3.0 and commit? [Y/n]: y
Committed VERSION at v1.3.0.
$ git b pre
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

## Compared with git-flow

The original [git-flow](https://github.com/nvie/gitflow) is archived, and points to
[git-flow-next](https://github.com/gittower/git-flow-next), Tower's Go rewrite: one binary,
presets for git flow, GitHub flow and GitLab flow, custom branch types and merge strategies,
and a VS Code extension. If what you want is git flow's commands, maintained, that's the one.

git-workflow is about the release around the branches:

- prereleases cut from the release branch and built by CI before the merge, and a release
  tagged on exactly the commit they tested ([why](docs/design.md#tag-what-was-tested))
- a `finish` that works through pull requests by default, on repositories where `main` only
  takes them, and from forks
- checks before anything is public: the version file, newer than the latest release, commits
  that aren't pushed or that no prerelease tested
- a committed `.gitworkflow` treated as someone else's file: every value checked, nothing run
  ([how](docs/design.md#someone-elses-files-are-data))
- your own git underneath: Bash on top of the commands you know, with `git b -vv` still being
  `git branch -vv`

## Install

git-workflow installs one program, `git-workflow`, which git runs as `git workflow` (git runs
any `git-<name>` on your `PATH` as `git <name>`; that's how `git lfs` plugs in too). The short
names, `git b`, `git c` and so on, are aliases you opt into, so git-workflow never takes a name
you already use.

It needs Bash 3.2 or newer (macOS's `/bin/bash` works) and Git 2.30 or newer. `finish` opens
pull requests with the [GitHub CLI](https://cli.github.com) (`gh`), or on GitLab with
[`glab`](https://gitlab.com/gitlab-org/cli) and `jq`; without them, set
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

[Verifying a release](docs/releasing.md#verifying-a-release) explains the key. The tarball includes the tests:
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

`make install` sets up completion for bash, zsh and fish. It completes the commands, `git b`
subcommands, the flow's branch types, `major`/`minor`/`patch`, and branch names, through your
aliases too (`git b fi<TAB>`).

- **bash**: installed where bash-completion finds it; git's own completion loads it the first
  time you complete a `git workflow` command. From a clone, source
  `completion/git-workflow.bash` from `~/.bashrc`.
- **zsh**: `_git-workflow` in `site-functions`, which zsh's git completion picks up. From a
  clone, put `completion/` on `$fpath` before `compinit`.
- **fish**: a `vendor_conf.d` snippet fish runs at startup. From a clone, source
  `completion/git-workflow.fish` from `config.fish`.

### Uninstalling and upgrading

`make uninstall` (with the same `PREFIX`) removes an install; your alias copies stay, and
`make unaliases` stops including them. `make help` lists every target.

**Upgrading from v2.x**: `finish` opens pull requests now. Your settings keep working
(`finishTopic`, `releasePrefix` and `hotfixPrefix` are read under their new names), but unset
`workflow.devBranch` if you set it globally: it's per repository now, and a global one would
make every repository git flow. To merge locally as before, see
[How `finish` integrates](docs/configuration.md#how-finish-integrates).

**Upgrading from v1.x**: `make install` removes the 1.x `git-*` commands from the same `PREFIX`
(git would run them instead of the new aliases), and `git workflow aliases install` replaces the
1.x alias include, keeping the extras (`git lg`, ...) it had. See the [CHANGELOG](CHANGELOG.md).

## Quick tour

### git flow

```sh
git b start topic fix-login     # from next, pushed
git c fix the login redirect    # commit; offers git add -A when nothing is staged
git b finish                    # pull request into next (or a merge, with integrate = merge)
git b start release minor       # release/v1.4.0 from next; offers to bump VERSION
git b pre                       # v1.4.0-rc.1 → CI publishes a prerelease; test it
git b finish                    # pull request into main; once merged, finish again tags v1.4.0
git b status                    # where you are, what's next, what's left to do
```

### GitHub flow

```sh
git b start topic fix-typo      # from main
git b finish                    # pull request into main; after the merge, deletes the branch
git b pre                       # on main: v1.4.0-rc.1, with the version from VERSION
git b release                   # tags exactly what rc.1 tested as v1.4.0
```

Forks, GitLab, and the release workflow these feed: [docs/releasing.md](docs/releasing.md).

## Commands

`git b` is `git workflow branch`; the other aliases are below. Every command is in
[docs/commands.md](docs/commands.md), and `git workflow help <command>` opens its manual page.

| Command                                          | Does                                                                       |
| ------------------------------------------------ | -------------------------------------------------------------------------- |
| `git b start <type> [name\|major\|minor\|patch]` | start a branch of one of the flow's types from the right base, and push it |
| `git b pre [label\|vX.Y.Z\|tag] [-n] [-l]`       | tag a release/hotfix branch (or `main`, in GitHub flow) as a prerelease    |
| `git b release [vX.Y.Z] [-n]`                    | GitHub flow: tag the newest prerelease's commit as the release             |
| `git b finish [branch]`                          | open a pull request, or merge per the flow; tag releases; clean up         |
| `git b delete [branch] [-y] [-f]`                | delete locally and on the remote, if it's merged                           |
| `git b status`                                   | where you are, what to run next, and what's left to do                     |
| `git b config`                                   | the flow, and every setting with where it came from                        |
| `git c [--amend] [message]`                      | commit with the message as plain words                                     |
| `git qc [p] [message]`                           | commit, sync with the remote branch, optionally push                       |
| `git ps [force]`                                 | sync with the remote branch, then push (`force`: with lease)               |
| `git sync [branch]`                              | fetch everything, then bring the branch up to date                         |
| `git rb-pull [branch]`                           | switch to a branch and bring it up to date                                 |
| `git sq [base]`                                  | squash the branch's own commits, without moving it                         |

`start`, `pre`, `release` and `finish` take `-y` to answer their questions with yes; flow
warnings still ask. `git b` with options is `git branch`, and any other word is an error, so
`git b finsh` doesn't create a branch named `finsh`.

## Configuration

Nothing to set up: the flow is guessed (a `next` or `develop` branch means git flow, anything
else GitHub flow), and `git b config` says what it guessed and why. Every setting is a
`workflow.*` git config key, or a line in a committed `.gitworkflow`:

```sh
git config workflow.integrate merge         # finish merges locally, one atomic push
git config workflow.strict true             # flow warnings become stops
git config workflow.versionFile package.json
git config workflow.tagPrefix ""            # tags are 1.2.3, not v1.2.3
```

```ini
# .gitworkflow, committed: everyone's git b follows it
[workflow]
    flow = gitflow
[workflow "release"]
    integrate = merge
```

[docs/configuration.md](docs/configuration.md) has every setting, the flows, writing your own,
versions, forges and the guardrails.

## Documentation

- [docs/commands.md](docs/commands.md): every command in detail
- [docs/configuration.md](docs/configuration.md): flows, settings, `.gitworkflow`, versions,
  forges, guardrails
- [docs/releasing.md](docs/releasing.md): GitHub flow and forks, the release workflow it pairs
  with, verifying a release
- [docs/design.md](docs/design.md): why it works the way it does
- `man git-workflow`, and `git workflow help <command>`

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
| `/usr/share/git-workflow/forges/`                     | what opens pull requests (`github.sh`, `gitlab.sh`)         |
| `/usr/share/git-workflow/aliases/`                    | the default alias sets                                      |
| `/usr/share/man/man1/git-workflow*.1`                 | man pages (`git workflow help <command>` opens a command's) |
| `/usr/share/bash-completion/completions/git-workflow` | bash completion, loaded by git's own                        |
| `/usr/share/zsh/site-functions/_git-workflow`         | zsh completion, found by zsh's git completion               |
| `/usr/share/fish/vendor_conf.d/git-workflow.fish`     | fish completion, run by fish at startup                     |
| `/usr/share/doc/git-workflow/`                        | README, CHANGELOG, LICENSE, and the `docs/` pages           |

`BINDIR`, `DATADIR`, `DOCDIR`, `MANDIR`, `COMPLETIONDIR`, `ZSHCOMPDIR` and `FISHCONFDIR` can be
overridden individually.
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
vhs docs/demo.tape  # record docs/demo.gif (https://github.com/charmbracelet/vhs)
```

With [GNU parallel](https://www.gnu.org/software/parallel/) installed (`pacman -S parallel` /
`apt install parallel` / `brew install parallel flock`), `make test` and `make installcheck`
run `JOBS` tests at a time. That's three per CPU by default, since bats looks for a free slot
only once a second; on macOS, `flock` saves it waiting a second at a time for its lock as well.
`make test JOBS=1` runs them in order.

Tests run each command against a throwaway bare remote and clone, with your global git config
and `~/.config` isolated and the default aliases installed. That fixture is built once per file
and copied into each test, so a test pays one `cp` for it instead of an aliases install and
about fifteen git processes. `tests/regressions.bats` has one test
per fixed bug, grouped by release; `tests/flows.bats` covers the full flows, guardrails and `-y`;
`tests/github-flow.bats` pull requests, releasing from `main` and forks (with a stand-in for
`gh`, and a remote whose `main` refuses pushes); `tests/forges.bats` GitLab (a stand-in for
`glab`), your own forges and release-run links; `tests/versions.bats` tag prefixes, version
files and `start release minor`; `tests/status.bats` `git b status`;
`tests/flow-config.bats` flows, settings layers and `.gitworkflow`; `tests/completion.bats`
bash, zsh and fish completion; `tests/cli.bats` the program itself, its help and the alias
sets. CI runs lint, the suite, and `installcheck` on Linux and macOS with its stock Bash 3.2,
on every push to a flow branch and on pull requests: the suite and `installcheck` as separate
jobs, all four at once. [docs/design.md](docs/design.md) explains how it all fits together.
