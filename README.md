# Joshua's Git Aliases

This repo contains my git aliases and will eventually be extended to use dedicated scripts. It enforces a somewhat simplified Git Flow structure.

To use the aliases, copy and paste the contents of the `git-workflow-aliases` file into `~/.gitconfig`

If you want to check them out, proceed with caution. I am new to computer science. I plan on moving the aliases into a stack of bash scripts.

I use `next` instead of `dev` because I don't want to rename the branch on my other project. Make sure the naming conventions I use match your use case.

## Start Branch

`git start [t/h/r] [name/version]`
- This command will start a topic branch, release branch, or hotfix branch.

#### What happens when you `start`:
- Firstly, the alias errors out if you have untracked files because autostash can't stash them properly.


- `topic`:
    1. Switch to next
    2. fetch and pull --rebase --autofetch
    3. Create topic branch as named and push to remote.


- `hotfix`:
    1. Switch to main
    2. fetch and pull --rebase --autofetch
    3. Create `hotfix/[tag]` branch and push to remote

- `release`:
    1. Switch to next.
    2. fetch and pull --rebase --autofetch
    3. Create `release/[tag]` branch and push to remote

## Finish Branch

`git finish`
- This command will automatically handle merging a topic branch, release branch, or hotfix branch.
- It detects the branch you are trying to finish, and asks for confirmation (errors out if you try to finish main or next)

#### What happens when you `finish`:
- Errors out if you have untracked files.
- Handles branching strategy.
- NOTE: needs work, currently may fail if it can't complete a fast forward from main to next.

- `topic`:
    1. Switch to next
    2. Non-FF merge the topic into next to maintain history
    3. Push and echo the command to delete (will be automated when I move these into scripts)

- `hotfix`or `release`:
    1. Switch to main
    2. Non-FF merge the hotfix or release branch into main branch
    3. Create new version tag
    3. Push and echo the command to delete (will be automated when I move these into scripts)

## Delete Branch

`git deleteBranch [name optional] [-y to skip confirmation - must use name]`
- This deletes the named branch or the current branch if you don't provide a name.
- Asks for confirmation unless you pass something like yes or -y. To skip confirmation, you have to reference the branch by name or it won't work.
- Prohibits deletion of `main` and `next` branches.
- Error out if you have untracked files in the branch (PLANNED: -D to skip this check)
- automatically switches to next if you are in the branch you want to delete, and switches back if you abort.
- Deletes local and remote.

## Sync

`git sync [name optional]`
- Switches to the named branch if you defined one.
- Stashes untracked files in the selected branch.
- do git pull --rebase to update the local copy of the branch.
- Pops untracked files out of stash (not autostash).

## Quick Commit and Push

`git qc "Message"`
- If you don't provide a message, it reads a response from you. It will abort with an empty response.
- If the branch is on the remote it updates the local version with pull --rebase --autostash.
- Adds TRACKED files (add -u), commits with the given message, and pushes to current  branch on the remote.

## All Aliases


| Command | Description |
| --------------------------------------------------------------------------- | ------- |
| `git s`:                                                                    |  short status |
| `git lg`:                                                                   | beautiful graph/log |
| `git graph`:                                                                | ugly graph/log |
| `git aa`:                                                                   | add tracked / modded files |
| `git sync [branch]`:                                                        | update a branch to the remote |
| `git c [message]`:                                                          | commit only without push |
| `git qc [message]`:                                                         | combines add -u, commit, and push to current remote branch |
| `git deleteBranch [branch name] [optional 'yes' to bypass confirmation]`:   | delete local and remote copy. pass without args to delete current branch |
| `git start [topic/release/hotfix] [name/tag]`:                              | start branches automatically for Git Flow strategy|
| `git finish`: |  run from the branch you want to finish, detects if release: merge to main and next, else merge to next |