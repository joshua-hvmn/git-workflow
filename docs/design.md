# Design notes

Why git-workflow works the way it does. The README and the man pages say what it does; this
is the reasoning behind it, for anyone changing the code, and for me in six months.

## Shape

One program, `bin/git-workflow`, which git runs as `git workflow`. It finds `share/`, resolves
the command, and sources `share/commands/<command>.sh`. The libraries are sourced, not run:
`core.sh` (settings, prompts, remote state), `release.sh` (versions and tags), `flow.sh`
(start, finish, delete), `status.sh`, and a forge.

The floor is Bash 3.2 and Git 2.30, because that's what a stock Mac has. CI runs the suite
with macOS's `/bin/bash`, so the floor is tested, not hoped for. In practice that rules out
associative arrays, `${var,,}`, `mapfile`, and empty arrays under `set -u`; settings are kept
in strings and read with parameter expansion instead.

Nothing to install beyond git. `gh` (or `glab` and `jq`) is needed only to open pull requests,
and `integrate = merge` doesn't need them at all.

## Settings are resolved once

Every command starts by sourcing `core.sh`, which reads every setting from one
`git config --show-scope` call, plus the repository's `.gitworkflow` and the flow file, into
a single string of `key<TAB>value<TAB>source` lines, later layers winning:

1. the flow file
2. what the repository looks like (its default branch, a `develop` branch)
3. your global git config
4. the repository's `.gitworkflow`
5. the repository's own git config
6. `git -c`

`.gitworkflow` sits above your global config so a repository's choices beat your defaults,
and below `.git/config` so your clone can still override the repository. Every value is
checked as it's read, problems are collected, and they're printed once.

`conf_get` finds a key with parameter expansion, not a loop: it runs dozens of times per
command, and in Bash 3.2 a `while read` over a here-string writes a temp file each time.
Remote URLs come from the same `git config` call. Each git process is a few milliseconds,
and they add up on every keystroke of tab completion.

## Someone else's files are data

A `.gitworkflow` comes with the repository you cloned, so nothing in it can make git-workflow
do something you didn't ask for:

- Every value is checked against the values the setting takes; a bad one is reported and
  ignored. Branch and remote names must be valid ones that don't start with `-`, so no value
  can become a git option.
- Includes aren't followed, and it can't set `remote` or `upstream`, which are about your
  clone, not the repository.
- Flow and forge names are lowercase words, so a name can't be a path.
- `versionFile` must be a path inside the repository, and `start` writes only a file git
  tracks.
- Control characters are stripped, so a printed value can't rewrite your terminal.
- Version files are read with awk. `package.json`, `Cargo.toml` and `pyproject.toml` are
  never handed to a tool that could run something in them, and there's no "version command"
  setting for the same reason.

Code runs only from `share/` and your own `~/.config/git-workflow/`: a `.gitworkflow` can pick
a forge by name, never supply one.

## Flows are data

Until v3, git flow was the code and "trunk mode" was a set of `TRUNK_MODE` checks spread
through it. Every new flow would have meant more of them. Now a flow is a file of settings
per branch type (where `start` branches it from, where `finish` takes it, how, where the tag
goes, what's merged back), and `flow.sh` is one engine driven by them. A flow that needs
something the settings can't express is a new value for a setting, not a new code path.

## Tag what was tested

The point of a release process is that what ships is what you tested, so:

- `git b pre` tags the release branch (or `main`, in GitHub flow) as `vX.Y.Z-rc.N` and pushes
  only that tag, so CI builds a real prerelease from it before anything reaches `main`.
- `finish` lists the prereleases, and flags commits after the last one.
- git flow tags the merge into `main`: `main` holds nothing but releases, so the merge is
  exactly the release branch. GitHub flow's hotfixes tag their tested tip instead, because
  `main` already has unreleased work, and a squash merge (whose commit nobody tested) is
  refused.
- `git b release` tags the commit the newest prerelease tested, not wherever `main` has got
  to, and says how many commits it's leaving for the next release.
- The version file must match before a tag is public, not after CI fails on it.

## finish, two ways

With `integrate = merge`, nothing is pushed until every local step has worked: merge, tag,
back-merge, then one `git push --atomic` of the branches and that one tag. Each step records
where the branches were, so any failure (a conflict, a diverged dev branch, a rejected push)
rolls everything back and leaves you on the branch you were finishing, ready to run it again.
Pushing one explicit tag, never `--tags`, keeps stray local tags off the remote, and GitHub
skips workflow runs when more than three tags arrive at once.

With pull requests (the default), `finish` is two steps: open the pull request; once it's
merged, run `finish` again to tag and clean up. Working out "is it merged?" goes from
cheapest to most expensive:

1. The branch's commits are on the target: a merge commit or a fast-forward. `merge_point`
   finds the commit that brought them in with one `rev-list --first-parent --ancestry-path`.
2. Its changes are: `git cherry` for a rebase merge, or, for a squash, a synthetic commit of
   the branch's whole diff checked with `git cherry`.
3. The forge says so. Then the pull request's head must contain the branch, or this is a
   branch name used again after an old pull request merged.

The second step is easy to forget, so `git b status` lists a versioned branch that's merged
but not tagged.

## Questions and guardrails

There are two kinds of prompt. A question ("Push 1 local commit first?") confirms something
you asked for. A flow warning ("commits after the last prerelease") says you're stepping
outside the flow. `-y` answers questions, never warnings; `workflow.strict` turns warnings
into stops. End of input declines, so a prompt with no terminal is a "no", never a hang.

## One fetch per command

Nearly all of a command's time is SSH round trips. `sync_remote` fetches once, from the
upstream remote with tags and from your fork without, and every "is it on the remote?"
question after that is answered from the remote-tracking refs. Pushes that can lose work use
`--force-with-lease --force-if-includes`, so a background fetch by your editor can't turn a
force-push into overwriting someone else's commits.

## Tests

The suite runs every command the way you'd type it, through the default aliases, against a
throwaway bare remote and a clone, with your git config and `~/.config` isolated. Building that
fixture is an aliases install and about fifteen git processes, half of what a typical test
costs, so `setup_file` builds it once per file and each test copies it, moving its few absolute
paths to the copy in Bash. Beyond that:

- a `pre-receive` hook stands in for branch protection (a `main` that only takes pull
  requests), and a second clone stands in for GitHub merging one
- fake `gh` and `glab` scripts answer with canned pull requests and log what they were asked
  to do
- `url.<path>.insteadOf` gives local repositories GitHub- and GitLab-shaped URLs
- zsh completion is driven through a real interactive zsh on a pseudo-terminal, and fish's
  with `complete -C`
- `make installcheck` runs the whole suite again against an installed copy in a path with a
  space in it, then checks that uninstall leaves nothing behind

Every test owns its repositories and config, so `make test` runs them in parallel with
`bats --jobs`, three per CPU, since bats looks for a free slot only once a second. With `--jobs`
a file's tests start together, so `setup` never builds the fixture; a file with a `setup_file`
of its own calls `fixture_build` from it. What's left is the commands themselves: a `git b`
command starts thirty to forty processes, four in five of the suite's, so a process saved in a
command is saved in every test that runs it.

Every fixed bug gets a test in `tests/regressions.bats`, grouped by the release that fixed it.
