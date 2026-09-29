# Changelog

## Unreleased

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
