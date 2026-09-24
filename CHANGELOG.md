# Changelog

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
