PREFIX  ?= $(HOME)/.local
BINDIR  := $(PREFIX)/bin
SRCDIR  := $(abspath scripts)
ALIASES := $(abspath alias-core/git-workflow-aliases)
SCRIPTS := $(notdir $(wildcard scripts/git-*))

.PHONY: install uninstall lint test

## install: symlink the git-* commands into $(BINDIR) and include the aliases in ~/.gitconfig
install:
	@mkdir -p "$(BINDIR)"
	@for s in $(SCRIPTS); do ln -sfn "$(SRCDIR)/$$s" "$(BINDIR)/$$s"; echo "linked $(BINDIR)/$$s"; done
	@git config --global --get-all include.path | grep -qxF "$(ALIASES)" \
		|| git config --global --add include.path "$(ALIASES)"
	@echo "aliases included from $(ALIASES)"
	@case ":$$PATH:" in *":$(BINDIR):"*) ;; *) echo "note: add $(BINDIR) to your PATH";; esac

## uninstall: remove the symlinks and the alias include
uninstall:
	@for s in $(SCRIPTS); do rm -f "$(BINDIR)/$$s"; done
	@git config --global --fixed-value --unset-all include.path "$(ALIASES)" 2>/dev/null || true
	@echo "uninstalled"

## lint: shellcheck every script
lint:
	cd scripts && shellcheck -x -P lib -e SC1091 git-* lib/*.sh


## test: run the bats suite (needs bats-core)
test:
	BATS_TEST_TIMEOUT=60 bats tests </dev/null
