# A recording of git-workflow for the README, made with vhs
# (https://github.com/charmbracelet/vhs). From the repository's root:
#
#   vhs docs/demo.tape        # writes docs/demo.gif
#
# It runs this checkout's bin/git-workflow in a throwaway repository and git
# config, so it touches nothing of yours.

Output docs/demo.gif

Set Shell bash
Set FontSize 15
Set Width 1100
Set Height 680
Set Padding 20
Set TypingSpeed 35ms
Set Theme "Catppuccin Mocha"

# A remote with main, next and a v1.3.2 release; a clone of it on next
Hide
Type `export PATH="$PWD/bin:$PATH" GIT_CONFIG_GLOBAL="$(mktemp)" XDG_CONFIG_HOME="$(mktemp -d)" PS1='$ '`
Enter
Type `git config --global user.name Demo; git config --global user.email demo@example.com; git config --global init.defaultBranch main; git config --global advice.detachedHead false; git config --global workflow.integrate merge; git workflow aliases install >/dev/null`
Enter
Type `d=$(mktemp -d); git init -q --bare "$d/remote.git"; git clone -q "$d/remote.git" "$d/app" 2>/dev/null; cd "$d/app"`
Enter
Type `echo v1.3.2 >VERSION; echo hello >app.txt; git add .; git commit -qm init; git tag -a v1.3.2 -m v1.3.2; git push -q origin main main:next v1.3.2; git switch -q next; clear`
Enter
Show

Type "git b status"
Enter
Sleep 2.5s

Type "git b start release minor"
Enter
Sleep 1.5s
Type "y"
Enter
Sleep 2s

Type `echo "a fix" >>app.txt && git commit -qam "fix the release"`
Enter
Sleep 1s

Type "git b pre"
Enter
Sleep 1.5s
Type "y"
Enter
Sleep 1s
Type "y"
Enter
Sleep 2s

Type "git b status"
Enter
Sleep 3s

Type "git b finish"
Enter
Sleep 1.5s
Type "y"
Enter
Sleep 1.5s
Type "y"
Enter
Sleep 2.5s

Type "git log --oneline --graph --decorate -7"
Enter
Sleep 4s
