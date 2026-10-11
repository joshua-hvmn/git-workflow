# Changelog

## v2.1.0

### Added

- Tab completion for bash: `git workflow` commands, `git b` subcommands, `start` modes,
  branch names for `finish`, `delete`, `pull` and `sync`, and the alias sets, through your
  aliases too (`git b fi<TAB>`). `make install` puts it in `COMPLETIONDIR`
  (`<prefix>/share/bash-completion/completions`), where git's completion loads it.
- `packaging/`: an AUR `PKGBUILD` and a Homebrew formula, and how to publish them.

### Changed

- `git workflow help`, `git b help`, `git b pre -h`, `git workflow aliases help` and
  `git b config` print to standard output, so they can be piped (`git b config | grep remote`).
  Errors and the usage printed after one still go to standard error.
- `git workflow help <command>` and `--help` open the checkout's own page when run from a
  checkout (`make link`), where `man` alone couldn't find it.
- The release workflow's publish job checks the tarball against the hash the build job
  computed before signing it, and Dependabot keeps the pinned actions up to date.
- `make lint` also checks formatting with `shfmt` and shellchecks the tests, when installed.

### Fixed

- A mistyped `git b` subcommand no longer creates a branch: `git b finsh` passed `finsh` to
  `git branch`. Options still pass through (`git b -vv`); any other word is an error.
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
