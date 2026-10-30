# Changelog

## v3.1.0

### Added

- **Versions beyond `vX.Y.Z` and `VERSION`.** `workflow.tagPrefix` (default `v`) is what comes
  before `X.Y.Z` in tags and branch names: `""` for `1.2.3`, `pkg-a/v` for one package of a
  monorepo. `workflow.versionFile` reads `package.json`, `Cargo.toml` (`[package]`, else
  `[workspace.package]`) and `pyproject.toml` (`[project]`, else `[tool.poetry]`) by name, with
  awk: nothing to install, and nothing in the file runs.
- **`git b start release minor`** (`major`, `patch`) starts the next version after the latest
  release, and a version typed without its `v` gets one. On a new release or hotfix branch,
  `start` offers to set the version file and commit it, keeping how the file writes it.
- **`-y`** for `start`, `pre`, `release` and `finish`: answer their questions with yes, so they
  can run from a script. Flow warnings still ask (or abort without a terminal, or in strict
  mode).

### Changed

- `git b delete`'s 1.x spellings of `-y` (`-d`, `--d`, `--delete`, `--y`, and `y`, `yes` or `d`
  after the branch name) warn that they go away in v4. `-d` read as `git branch -d`.
- `workflow.versionFile` must be a path inside the repository, since `start` can write to it
  and a `.gitworkflow` can set it.
- `make test`, `make check` and `make installcheck` run the suite in parallel, `JOBS` tests at a
  time (three per CPU), when GNU parallel is installed; `JOBS=1` runs it in order. Each test
  copies a fixture built once per file instead of building its own, which halves what a test
  costs before it starts.

### Fixed

- `finish` on a merged pull request found the merge with one `git merge-base` per commit `main`
  had gained since: 600 commits took 4.5 s. It's one `git rev-list` now.

## v3.0.0

### Changed

- **Flows are data, not code.** A flow is a file of `workflow.*` settings: where each branch
  type starts, what `finish` integrates it into, how, where the tag goes and what's merged back.
  Two ship, `gitflow` and `github` (in `share/flows/`), and one in
  `~/.config/git-workflow/flows/<name>` is a flow too, with branch types of its own if it likes.
  `workflow.flow` picks one; unset, it's guessed from the branches (`next` or `develop` means git
  flow), and `git b config` says so.
- **`finish` opens a pull request by default** (`workflow.integrate`, default `pr`), so it's safe
  on repositories you don't own. Run it again once the pull request is merged, however it was
  merged: it deletes the branch, and for a release or hotfix tags it and pushes only the tag (in
  git flow, then opens the back-merge pull request into the dev branch). To merge locally as
  before: `git config workflow.integrate merge`, for the flow or per branch type
  (`workflow.release.integrate`).
- Settings are read in layers: the flow, what the repository looks like, your global config, the
  repository's `.gitworkflow`, its `.git/config`, then `git -c`. `git b config` shows where each
  one came from. `workflow.mainBranch` defaults to the remote's default branch (`master`, say).
- `git b start <type>` takes any of the flow's branch types. The 2.x names still work:
  `workflow.releasePrefix` and `workflow.hotfixPrefix` are `workflow.<type>.prefix`, and
  `workflow.finishTopic` is `workflow.topic.integrate`. A global `workflow.devBranch` now
  applies to every repository, so unset it and let each one's be worked out.

### Added

- `.gitworkflow`: a repository commits its flow and settings, and every contributor's `git b`
  follows it. It's read as data: values are checked, branch names validated, includes not
  followed, and it can't set your remotes.
- GitHub flow releases from `main`: `git b pre` on `main` tags `vX.Y.Z-rc.N` (version from
  `VERSION`, or `git b pre vX.Y.Z`), and the new `git b release [vX.Y.Z]` tags the newest
  prerelease's commit as `vX.Y.Z`, pushing only the tag. The release is exactly what was tested.
- Forks: `workflow.upstream` (default: a remote named `upstream`) is where `main`, the dev
  branch and the tags come from, and where pull requests go, from `<you>:<branch>`. Your
  branches go to `workflow.remote`, your fork.
- Forges: pull requests go through `share/forges/<workflow.forge>.sh`; `github` (with `gh`)
  ships. Another host is another file with the same six functions.
- `git b delete` counts a branch whose pull request was squash- or rebase-merged as merged.
- `git b finish` flags a release branch with commits after its last prerelease.
- `git b pre vX.Y.Z` names the version on any branch.
- Where a branch only takes pull requests, `git ps` and `git qc p` refuse to push it (`qc`
  before committing) and say how to move the commits to a branch.
- Tab completion for `release`, the flow's own branch types, and remote branches for `pull`
  and `sync`.
- This repository's own `.gitworkflow`: git flow, topics by pull request, releases merged
  locally.

### Fixed

- Trunk mode tagged the merge commit on `main`, so a release also shipped whatever reached
  `main` after its prereleases. GitHub flow tags the tested commit.
- Trunk mode started hotfixes from `main`, shipping its unreleased work. GitHub flow starts them
  from the latest release tag.

## v2.1.0

### Added

- Tab completion for bash: `git workflow` commands, `git b` subcommands, `start` modes,
  branch names for `finish`, `delete`, `pull` and `sync`, and the alias sets, through your
  aliases too (`git b fi<TAB>`). `make install` puts it in `COMPLETIONDIR`
  (`<prefix>/share/bash-completion/completions`), where git's completion loads it.
- `packaging/`: an AUR `PKGBUILD` and a Homebrew formula, and how to publish them.

### Changed

- `git b <word>` no longer passes an unknown word to `git branch`: a mistyped subcommand
  (`git b finsh`) used to create a branch by that name. Options still pass through
  (`git b -vv`); create a branch outside the flow with `git branch <name>`.
- `git workflow help`, `git b help`, `git b pre -h`, `git workflow aliases help` and
  `git b config` print to standard output, so they can be piped (`git b config | grep remote`).
  Errors and the usage printed after one still go to standard error.
- `git workflow help <command>` and `--help` open the checkout's own page when run from a
  checkout (`make link`), where `man` alone couldn't find it.
- The release workflow's publish job checks the tarball against the hash the build job
  computed before signing it, and Dependabot keeps the pinned actions up to date.
- `make lint` also checks formatting with `shfmt` and shellchecks the tests, when installed.

### Fixed

- Answering a prompt with end of input (Ctrl-D) printed "Aborted." twice.
- `git b finish` no longer prints git's "Already on '<branch>'".

## v2.0.0

### Changed

- **One program, `git workflow`, replaces the seven `git-*` commands.** Each command has a
  name (`git workflow branch`, `commit`, `quick-commit`, `push`, `sync`, `pull`, `squash`),
  and the 1.x names work too (`git workflow b`, `c`, `qc`, `ps`, `sq`, `rb-pull`). Installing
  no longer puts `git-b`, `git-c`, ... on your `PATH`, where git ran them ahead of your own
  aliases of the same name, and where `git-sync` clashed with git-extras.
- **`git b`, `git c` and the rest are now aliases you opt into**:
  `git workflow aliases install` (or `make aliases`) copies the `commands` alias
  set to `~/.config/git-workflow/aliases/` and includes it from `~/.gitconfig`. The general
  purpose `extras` alias set (`git lg`, `git s`, ...) is opt-in: `git workflow aliases install
extras`. The copies are yours to edit; install never overwrites them and leaves out any alias
  you already have in `~/.gitconfig` or a file it includes.
- Messages name commands the way you type them: `git ps force` with the default aliases,
  your own alias if you renamed it, `git workflow push force` with none.
- Man pages are `git-workflow(1)` and one `git-workflow-<command>(1)` per command; the 1.x
  overview in section 7 is now `git-workflow(1)`. `git workflow help <command>` and
  `git workflow <command> --help` open a command's page.
- Installed layout: `bin/git-workflow`, and `share/git-workflow/` holding the libraries,
  `commands/` and the default `aliases/`. `make install` and `make uninstall` remove 1.x files
  from the same `PREFIX`. `LIBDIR` is gone; the program finds everything through `DATADIR`.

### Added

- `git workflow help` lists the commands with your alias for each.
- `git workflow aliases [list | install | reset | remove]`.

### Fixed

- Commands run outside a repository stop with git's own "not a repository" instead of
  failing partway: `git c` printed the whole `git diff` usage and `git ps` claimed a detached
  HEAD.
- `make link` and `make unlink` remove the symlinks 1.x's link commands left in `LINKDIR`.

### Migrating from 1.x

1. Install 2.0 with the same `PREFIX` as before. It removes the 1.x commands, libraries and
   man pages there. If 1.x lived under another `PREFIX`, run its `make uninstall` too, or
   `git workflow aliases install` will warn that an old `git-b` (say) still runs instead of
   the alias.
2. Run `git workflow aliases install`. It removes the 1.x include of `git-workflow-aliases`
   and sets up `git b`, `git c`, ... as before, plus `git lg` and the other extras from 1.x.
3. Scripts that ran `git-b` directly should run `git workflow branch` (or `git b`).

## v1.4.2

### Changed

- The libraries and `VERSION` install to `share/git-workflow/` instead of `lib/git-workflow/`.
  `make uninstall` removes both locations.

### Fixed

- Pulling a topic or release branch no longer undoes work. After `git sq`, `git b finish`,
  `git qc p` and `git sync` stop and say to run `git ps force` instead of rebasing the old
  commits back in. After merging the dev or main branch in to fix a `finish` conflict,
  running `finish` again no longer starts a rebase that repeats the conflict.
- `git b start` checks the branch name before switching to the base branch.
- A `workflow.releasePrefix` without a trailing slash (like `release-`) now finds open
  release branches.
- The release workflow accepts a `VERSION` of `1.2.3` as well as `v1.2.3`, like
  `git b pre` and `git b finish` do.
- Removed a reference to a PKGBUILD template in the README that is now delayed.

## v1.4.1

### Fixed

- Release notes now come from the CHANGELOG section. v1.4.0 wrote them to the wrong path,
  so its release used notes generated from commits.

## v1.4.0

### Changed

- **`make install` now copies files into `PREFIX` (default `/usr/local`)** instead of
  symlinking into `~/.local/bin` and editing `~/.gitconfig`. It honors `DESTDIR`, `BINDIR`,
  `LIBDIR`, `DATADIR`, `DOCDIR` and `MANDIR`, so distro packages can use it as is. The old
  behavior is now `make link` (symlinks) plus `make aliases` (the `~/.gitconfig` include).
  If you installed an earlier version with `make install`, run the old `make uninstall`
  before upgrading.
- `git qc push ...` no longer means push mode: only `p`, `-p` or `--push` do.
- `git c` / `git qc` refuse a leading `-` instead of committing it as text. Use `--` for a
  message that starts with a dash.
- `git b delete` refuses a branch with unmerged commits unless given `-f`.
- The commands run `#!/usr/bin/env bash`, and find their libraries from a path filled in at
  install time rather than an exported `GIT_SCRIPTS_HOME_DIR`.

### Added

- `workflow.finishTopic=pr`: `git b finish` on a topic branch pushes it and opens a pull
  request with `gh`, for repos whose dev branch requires reviews.
- `workflow.versionFile` (default `VERSION`): `git b pre` and `git b finish` check it matches
  the version being tagged, before anything is public.
- Man pages: `git-workflow(7)` and one per command; `git b --help` now opens `git-b(1)`.
- `make link`/`unlink`, `make aliases`/`unaliases`, `make check`, `make installcheck`,
  `make dist`, `make help`.
- `git b delete -f`, and deleting a branch that only exists on the remote.
- Arch Linux PKGBUILD template in `packaging/arch/`.
- CI runs on macOS with its stock Bash 3.2 and tests an installed copy.
- Release notes come from this changelog.
- Release tarballs are GPG-signed ('.sig') and carry a GitHub build provenance attestation.
  Publishing waits for approval in the 'release' environment, which holds the signing key;
  building and testing run in a separate job that has no access to it.

### Fixed

- `git b finish` rolls back any failure, not only a rejected push: a rejected topic push,
  a merge conflict, a diverged dev branch, or a back-merge conflict used to leave unpushed
  merges on `main`/`devBranch`, so rerunning finish stopped at "diverged".
- `git c` now warns before committing on a protected branch, as the README said it did.
- `git ps force` adds `--force-if-includes`, so commits that only arrived through a
  background fetch are never overwritten; force-pushing a protected branch always stops.
- `git ps` detects a branch that was rewritten after it was pushed and says to use
  `git ps force`, instead of rebasing the rewrite back onto the old commits.
- `git sq` squashes hotfix branches against `main`, and says when a squash needs
  `git ps force`.
- `git b start` refuses a branch name that already exists on the remote, and no longer
  refuses untracked files.
- `git b delete` fetches before checking the remote, checks everything before switching
  branches, and no longer treats `-y` alone as a branch name.
- Version comparison no longer depends on `sort -V`.
- `git ps` rejects unknown arguments instead of ignoring them.

## v1.3.0

### Fixed

- `git qc`: partially staged changes are no longer lost. It now commits before syncing;
  syncing first autostashed and restored everything unstaged, then offered `git add -A`.
- `git b finish`: a rejected atomic push now prints the retry command and offers to roll back
  the local merge and tag, so finish can be run again (it used to stop at "tag already exists").
- `git b start` / `finish` work on a fresh clone: a missing local `main`/`devBranch` is
  created from the remote.
- `git b finish` / `delete` refuse to run with uncommitted changes instead of carrying them
  onto `devBranch`.
- `git c` / `git qc`: every word is part of the message (`git c fix the bug`).
- `git ps` / `git qc p` push to `workflow.remote` instead of a hardcoded `origin`.
- `git ps` / `git qc p` refuse to push from a detached HEAD.
- `git b pre -n` never prompts or aborts; `git b pre -l` skips flow checks.
- `git c --amend` with no message keeps the previous message.
- `git sq` squashes against `<remote>/<devBranch>` with `--keep-base`, warns on protected
  branches, and honors `workflow.remote`.
- A branch can be named `null`.

### Added

- `git b version`, backed by a `VERSION` file.
- bats test suite (`make test`) and CI workflow.
- Tag-triggered release workflow for this repo, usable as a template.

### Removed

- The `TEST_MODE` git mock. It could be triggered by an unrelated `TEST_MODE` variable
  in the environment; the bats suite replaces it.
