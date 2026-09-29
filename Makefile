# git-workflow
#
# Two ways to install:
#
#   make install        Copy files into PREFIX (default /usr/local). This is the
#                       standard layout a distro package uses:
#                         make install PREFIX=/usr DESTDIR="$pkgdir"
#                       Never touches your home directory or ~/.gitconfig.
#
#   make link           Developer install: symlink the commands in this checkout
#                       into LINKDIR (default ~/.local/bin), so edits here take
#                       effect immediately. Undo with `make unlink`.
#
# The aliases are opt-in either way: `make aliases` / `make unaliases`.

NAME    := git-workflow
VERSION := $(shell cat VERSION)

PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin
LIBDIR  ?= $(PREFIX)/lib/$(NAME)
DATADIR ?= $(PREFIX)/share/$(NAME)
DOCDIR  ?= $(PREFIX)/share/doc/$(NAME)
MANDIR  ?= $(PREFIX)/share/man
LINKDIR ?= $(HOME)/.local/bin

# Where `make aliases` points ~/.gitconfig: this checkout by default. After a
# packaged install use: make aliases ALIASES_FILE=/usr/share/git-workflow/git-workflow-aliases
ALIASES_FILE ?= $(CURDIR)/alias-core/git-workflow-aliases

SCRIPTS := $(notdir $(wildcard scripts/git-*))
LIBS    := $(wildcard scripts/lib/*.sh)
MAN1    := $(wildcard man/*.1)
MAN7    := $(wildcard man/*.7)

# `make dist` archives this ref under this name (the release workflow passes the tag)
DIST_REF  ?= HEAD
DIST_NAME ?= $(NAME)-$(VERSION)

.PHONY: all help install uninstall link unlink aliases unaliases \
	lint test check installcheck dist

## all: nothing to build (plain Bash); here so a bare `make` does no harm
all:
	@:

## help: list the targets
help:
	@sed -n 's/^## //p' $(MAKEFILE_LIST)

## install: copy commands, libraries, man pages and docs into PREFIX (honors DESTDIR)
install:
	mkdir -p "$(DESTDIR)$(BINDIR)" "$(DESTDIR)$(LIBDIR)" "$(DESTDIR)$(DATADIR)" \
		"$(DESTDIR)$(DOCDIR)" "$(DESTDIR)$(MANDIR)/man1" "$(DESTDIR)$(MANDIR)/man7"
	@# Fill in the library path. In the checkout it's found next to the script.
	@for s in $(SCRIPTS); do \
		out="$(DESTDIR)$(BINDIR)/$$s"; \
		sed 's|^GIT_WORKFLOW_LIBDIR=$$|GIT_WORKFLOW_LIBDIR="$(LIBDIR)"|' "scripts/$$s" >"$$out.tmp" && \
		grep -q '^GIT_WORKFLOW_LIBDIR="$(LIBDIR)"$$' "$$out.tmp" || { \
			echo "error: scripts/$$s has no 'GIT_WORKFLOW_LIBDIR=' line to fill in" >&2; \
			rm -f "$$out.tmp"; exit 1; }; \
		chmod 755 "$$out.tmp" && mv -f "$$out.tmp" "$$out" && echo "installed $$out"; \
	done
	install -m 644 $(LIBS) VERSION "$(DESTDIR)$(LIBDIR)/"
	install -m 644 alias-core/git-workflow-aliases "$(DESTDIR)$(DATADIR)/"
	install -m 644 README.md CHANGELOG.md LICENSE "$(DESTDIR)$(DOCDIR)/"
	install -m 644 $(MAN1) "$(DESTDIR)$(MANDIR)/man1/"
	install -m 644 $(MAN7) "$(DESTDIR)$(MANDIR)/man7/"

## uninstall: remove what `make install` put in PREFIX (use the same PREFIX/DESTDIR)
uninstall:
	for s in $(SCRIPTS); do rm -f "$(DESTDIR)$(BINDIR)/$$s"; done
	for m in $(notdir $(MAN1)); do rm -f "$(DESTDIR)$(MANDIR)/man1/$$m"; done
	for m in $(notdir $(MAN7)); do rm -f "$(DESTDIR)$(MANDIR)/man7/$$m"; done
	rm -rf "$(DESTDIR)$(LIBDIR)" "$(DESTDIR)$(DATADIR)" "$(DESTDIR)$(DOCDIR)"

## link: developer install - symlink this checkout's commands into LINKDIR (~/.local/bin)
link:
	@mkdir -p "$(LINKDIR)"
	@for s in $(SCRIPTS); do ln -sfn "$(CURDIR)/scripts/$$s" "$(LINKDIR)/$$s"; echo "linked $(LINKDIR)/$$s"; done
	@case ":$$PATH:" in *":$(LINKDIR):"*) ;; *) echo "note: add $(LINKDIR) to your PATH";; esac

## unlink: remove the symlinks made by `make link` (only if they point into this checkout)
unlink:
	@for s in $(SCRIPTS); do \
		l="$(LINKDIR)/$$s"; \
		if [ -L "$$l" ] && [ "$$(readlink "$$l")" = "$(CURDIR)/scripts/$$s" ]; then rm -f "$$l" && echo "removed $$l"; fi; \
	done

## aliases: include the alias file from ~/.gitconfig (git s, git lg, ...)
aliases:
	@git config --global --get-all include.path | grep -qxF "$(ALIASES_FILE)" \
		|| git config --global --add include.path "$(ALIASES_FILE)"
	@echo "~/.gitconfig includes $(ALIASES_FILE)"

## unaliases: remove that include again
unaliases:
	@git config --global --fixed-value --unset-all include.path "$(ALIASES_FILE)" 2>/dev/null || true
	@echo "~/.gitconfig no longer includes $(ALIASES_FILE)"

## lint: shellcheck the commands, libraries and test helper 
lint:
	cd scripts && shellcheck -x -P lib -e SC1091 git-* lib/*.sh
	shellcheck -s bash tests/test_helper.bash

## test: run the bats suite against this checkout (needs bats-core)
test:
	BATS_TEST_TIMEOUT=60 bats tests </dev/null

## check: same as test (the name distro packaging tools expect)
check: test

## installcheck: install into a temporary PREFIX and run the suite against that copy
installcheck:
	@tmp=$$(mktemp -d) && trap 'rm -rf "$$tmp"' EXIT && \
		$(MAKE) --no-print-directory install PREFIX="$$tmp" >/dev/null && \
		echo "testing the copy installed in $$tmp" && \
		GIT_WORKFLOW_BIN="$$tmp/bin" BATS_TEST_TIMEOUT=60 bats tests </dev/null

## dist: source tarball + sha256 of DIST_REF (what the release workflow publishes)
dist:
	git archive --format=tar.gz --prefix="$(DIST_NAME)/" -o "$(DIST_NAME).tar.gz" "$(DIST_REF)"
	sha256sum "$(DIST_NAME).tar.gz" >"$(DIST_NAME).tar.gz.sha256" 2>/dev/null \
		|| shasum -a 256 "$(DIST_NAME).tar.gz" >"$(DIST_NAME).tar.gz.sha256"
	@echo "wrote $(DIST_NAME).tar.gz"
