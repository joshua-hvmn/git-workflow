# ==============================================================================
# git-workflow
#
# Plain Bash, so there is nothing to build. `make install` copies the commands,
# their libraries, the man pages and the docs into PREFIX, and writes the
# library path into each command. `make help` lists the targets and shows the
# configuration.
#
#   sudo make install                           system-wide, into /usr/local
#   make install PREFIX="$HOME/.local"          for your user only
#   make install PREFIX=/usr DESTDIR="$pkgdir"  staged, for a distro package
#   make link                                   run this checkout (development)
#
# Pass the same PREFIX and DESTDIR to every target, uninstall included. Output
# is one line per file; V=1 prints the commands instead.
#
# Requires GNU make 3.81 or newer (macOS ships 3.81), a POSIX shell, awk and
# install(1). Nothing here needs GNU coreutils.
# ==============================================================================
 
NAME    := git-workflow
VERSION := $(shell cat VERSION)
 
# --- Tools --------------------------------------------------------------------
 
SHELL           := /bin/sh
INSTALL         ?= install
INSTALL_PROGRAM ?= $(INSTALL) -m 755
INSTALL_DATA    ?= $(INSTALL) -m 644
MKDIR_P         ?= mkdir -p
AWK             ?= awk
GIT             ?= git
BATS            ?= bats
SHELLCHECK      ?= shellcheck
MANDOC          ?= mandoc
 
# --- Install locations --------------------------------------------------------
# The libraries are sourced Bash, the same on every architecture, so they go in
# share/ (lib/ is for architecture-dependent files).
 
DESTDIR ?=
PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin
DATADIR ?= $(PREFIX)/share/$(NAME)
LIBDIR  ?= $(DATADIR)
DOCDIR  ?= $(PREFIX)/share/doc/$(NAME)
MANDIR  ?= $(PREFIX)/share/man
LINKDIR ?= $(HOME)/.local/bin
 
# The file `make aliases` includes from ~/.gitconfig. Empty means the installed
# copy in DATADIR if there is one, otherwise this checkout's.
ALIASES_FILE ?=
 
# --- Files --------------------------------------------------------------------
 
SCRIPTS := $(notdir $(wildcard scripts/git-*))
LIBS    := $(wildcard scripts/lib/*.sh) VERSION
MAN1    := $(wildcard man/*.1)
MAN7    := $(wildcard man/*.7)
DOCS    := README.md CHANGELOG.md LICENSE
ALIASES := alias-core/$(NAME)-aliases
 
# The command that install and uninstall check for
PROBE := $(firstword $(SCRIPTS))
 
# Before 1.4.2 the libraries went here; uninstall removes them from there too
OLD_LIBDIR := $(PREFIX)/lib/$(NAME)
 
# `make dist` archives this ref under this name (the release workflow passes the tag)
DIST_REF  ?= HEAD
DIST_NAME ?= $(NAME)-$(VERSION)
 
# --- Guards -------------------------------------------------------------------
# Checked before any target runs. Paths are quoted everywhere, so spaces are fine.
 
# Only bash expands the ~ in PREFIX=~/.local. fish, zsh and sh pass it through,
# and the recipes would then create a directory literally named "~" in this one.
ifneq ($(findstring ~,$(DESTDIR)$(PREFIX)$(BINDIR)$(LIBDIR)$(DATADIR)$(DOCDIR)$(MANDIR)$(LINKDIR)),)
  $(error A path contains a "~" that your shell did not expand. Use $$HOME instead: PREFIX="$$HOME/.local")
endif
 
# LIBDIR is written into the installed commands, which can run from any directory.
ifneq ($(patsubst /%,/,$(firstword $(LIBDIR))),/)
  $(error LIBDIR must be an absolute path, because the installed commands use it to find their libraries. It is "$(LIBDIR)")
endif
 
# --- Output -------------------------------------------------------------------
# One aligned line per action, the convention of git's and Linux's Makefiles.
 
V ?= 0
ifeq ($(V),1)
  Q   :=
  say := :
else
  Q   := @
  say := printf '  %-8s %s\n'
endif
 
# --- Recipe helpers -----------------------------------------------------------
 
# $(call install_files,DIR,COMMAND,FILES): install each file into DESTDIR/DIR
install_files = for f in $(3); do \
		dest="$(DESTDIR)$(1)/$$(basename "$$f")"; \
		$(say) INSTALL "$$dest"; \
		$(2) "$$f" "$$dest" || exit 1; \
	done
 
# $(call remove_files,DIR,NAMES): remove each name from DESTDIR/DIR, reporting
# only the files that were there
remove_files = for f in $(2); do \
		path="$(DESTDIR)$(1)/$$f"; \
		if [ -e "$$path" ] || [ -L "$$path" ]; then \
			$(say) RM "$$path"; \
			$(RM) "$$path" || exit 1; \
		fi; \
	done
 
# $(call path_note,DIR): after a real (unstaged) install into DIR, say when the
# commands can't be found, or when another copy earlier on PATH runs instead
path_note = [ -n "$(DESTDIR)" ] || { \
		found=$$(command -v $(PROBE) || true); \
		case $$found in \
		"$(1)/$(PROBE)") ;; \
		"") echo "note: $(1) is not on your PATH" ;; \
		*) echo "note: $$found comes first on your PATH, so it runs instead" ;; \
		esac; \
	}
 
# --- Targets ------------------------------------------------------------------
 
# No implicit rules: nothing here is built from anything else
.SUFFIXES:
 
.PHONY: all help install uninstall aliases unaliases link unlink \
	lint test check installcheck dist clean
 
all:
	@:
 
help:
	@echo "$(NAME) $(VERSION)"
	@$(AWK) 'BEGIN { FS = ":.*## " } \
		/^##@ / { printf "\n%s:\n", substr($$0, 5) } \
		/^[a-z][a-z-]*:.*## / { printf "  %-14s %s\n", $$1, $$2 }' $(MAKEFILE_LIST)
	@echo
	@echo "Configuration (set any of these on the command line):"
	@printf '  %-14s %s\n' \
		PREFIX  '$(PREFIX)'  DESTDIR '$(or $(DESTDIR),(none))' \
		BINDIR  '$(BINDIR)'  DATADIR '$(DATADIR)' \
		LIBDIR  '$(LIBDIR)'  DOCDIR  '$(DOCDIR)' \
		MANDIR  '$(MANDIR)'  LINKDIR '$(LINKDIR)'
 
##@ Install
 
install: all ## Copy the commands, libraries, man pages and docs into PREFIX
	$(Q)$(MKDIR_P) "$(DESTDIR)$(BINDIR)" "$(DESTDIR)$(LIBDIR)" "$(DESTDIR)$(DATADIR)" \
		"$(DESTDIR)$(DOCDIR)" "$(DESTDIR)$(MANDIR)/man1" "$(DESTDIR)$(MANDIR)/man7"
	$(Q)$(call install_files,$(LIBDIR),$(INSTALL_DATA),$(LIBS))
	$(Q)$(call install_files,$(DATADIR),$(INSTALL_DATA),$(ALIASES))
	$(Q)$(call install_files,$(DOCDIR),$(INSTALL_DATA),$(DOCS))
	$(Q)$(call install_files,$(MANDIR)/man1,$(INSTALL_DATA),$(MAN1))
	$(Q)$(call install_files,$(MANDIR)/man7,$(INSTALL_DATA),$(MAN7))
# Commands last, so an interrupted install never leaves a command that can't
# find its libraries. Each one's empty GIT_WORKFLOW_LIBDIR= line (a checkout
# leaves it empty and looks next to the script) gets LIBDIR. awk rather than
# sed: LIBDIR comes in through the environment, so nothing in it needs
# escaping, and the exit status says whether the line was there exactly once.
	$(Q)stage=$$(mktemp -d) && trap 'rm -rf "$$stage"' EXIT && \
	for s in $(SCRIPTS); do \
		LIBDIR="$(LIBDIR)" $(AWK) ' \
			$$0 == "GIT_WORKFLOW_LIBDIR=" { print "GIT_WORKFLOW_LIBDIR=\"" ENVIRON["LIBDIR"] "\""; n++; next } \
			{ print } \
			END { exit (n != 1) }' "scripts/$$s" >"$$stage/$$s" || { \
			echo "error: scripts/$$s needs exactly one empty GIT_WORKFLOW_LIBDIR= line" >&2; \
			exit 1; \
		}; \
		$(say) INSTALL "$(DESTDIR)$(BINDIR)/$$s"; \
		$(INSTALL_PROGRAM) "$$stage/$$s" "$(DESTDIR)$(BINDIR)/$$s" || exit 1; \
	done
	$(Q)$(call path_note,$(BINDIR))
 
uninstall: ## Remove what install put in PREFIX (pass the same PREFIX and DESTDIR)
	$(Q)[ -e "$(DESTDIR)$(BINDIR)/$(PROBE)" ] || \
		echo "note: no $(NAME) in $(DESTDIR)$(BINDIR). Was it installed with another PREFIX?"
# The reverse of install: commands first, then what they use
	$(Q)$(call remove_files,$(BINDIR),$(SCRIPTS))
	$(Q)$(call remove_files,$(LIBDIR),$(notdir $(LIBS)))
	$(Q)$(call remove_files,$(OLD_LIBDIR),$(notdir $(LIBS)))
	$(Q)$(call remove_files,$(DATADIR),$(notdir $(ALIASES)))
	$(Q)$(call remove_files,$(DOCDIR),$(DOCS))
	$(Q)$(call remove_files,$(MANDIR)/man1,$(notdir $(MAN1)))
	$(Q)$(call remove_files,$(MANDIR)/man7,$(notdir $(MAN7)))
# Only this project's own directories, and only once they're empty (LIBDIR
# first, in case it was set to a directory inside DATADIR)
	$(Q)for d in "$(DESTDIR)$(LIBDIR)" "$(DESTDIR)$(DATADIR)" "$(DESTDIR)$(DOCDIR)" "$(DESTDIR)$(OLD_LIBDIR)"; do \
		if [ -d "$$d" ] && rmdir "$$d" 2>/dev/null; then $(say) RMDIR "$$d"; fi; \
	done
 
aliases: ## Include the alias file (git s, git lg, ...) from ~/.gitconfig
	$(Q)file='$(ALIASES_FILE)'; \
	if [ -z "$$file" ]; then \
		file="$(DATADIR)/$(notdir $(ALIASES))"; \
		[ -f "$$file" ] || file="$(CURDIR)/$(ALIASES)"; \
	fi; \
	if $(GIT) config --global --get-all include.path | grep -qxF "$$file"; then \
		echo "~/.gitconfig already includes $$file"; \
	else \
		$(GIT) config --global --add include.path "$$file" && \
		echo "~/.gitconfig now includes $$file"; \
	fi
 
unaliases: ## Remove that include, whichever copy it points at
	$(Q)removed=; \
	for file in '$(ALIASES_FILE)' "$(DATADIR)/$(notdir $(ALIASES))" "$(CURDIR)/$(ALIASES)"; do \
		[ -n "$$file" ] || continue; \
		if $(GIT) config --global --get-all include.path | grep -qxF "$$file"; then \
			$(GIT) config --global --fixed-value --unset-all include.path "$$file" || exit 1; \
			echo "~/.gitconfig no longer includes $$file"; \
			removed=1; \
		fi; \
	done; \
	[ -n "$$removed" ] || echo "~/.gitconfig includes no $(NAME) alias file"
 
##@ Development
 
link: ## Symlink this checkout's commands into LINKDIR, so edits take effect at once
	$(Q)$(MKDIR_P) "$(LINKDIR)"
	$(Q)for s in $(SCRIPTS); do \
		$(say) LINK "$(LINKDIR)/$$s"; \
		ln -sfn "$(CURDIR)/scripts/$$s" "$(LINKDIR)/$$s" || exit 1; \
	done
	$(Q)$(call path_note,$(LINKDIR))
 
unlink: ## Remove the symlinks link made (only those pointing into this checkout)
	$(Q)for s in $(SCRIPTS); do \
		l="$(LINKDIR)/$$s"; \
		if [ -L "$$l" ] && [ "$$(readlink "$$l")" = "$(CURDIR)/scripts/$$s" ]; then \
			$(say) RM "$$l"; \
			$(RM) "$$l" || exit 1; \
		fi; \
	done
 
lint: ## Shellcheck the commands, libraries and test helper; lint the man pages
	@$(say) LINT "scripts/git-* scripts/lib/*.sh"
	$(Q)cd scripts && $(SHELLCHECK) -x -P lib -e SC1091 git-* lib/*.sh
	@$(say) LINT tests/test_helper.bash
	$(Q)$(SHELLCHECK) -s bash tests/test_helper.bash
	$(Q)if command -v $(MANDOC) >/dev/null 2>&1; then \
		$(say) LINT "man/*"; \
		$(MANDOC) -Tlint -W warning $(MAN1) $(MAN7); \
	else \
		echo "note: $(MANDOC) is not installed, so the man pages were not linted"; \
	fi
 
# Tests run with stdin closed: one that would wait for an answer fails instead
# of hanging, and BATS_TEST_TIMEOUT stops one that hangs anyway.
test: ## Run the bats suite against this checkout
	@$(say) TEST tests
	$(Q)BATS_TEST_TIMEOUT=60 $(BATS) tests </dev/null
 
check: test ## Same as test (the name packaging tools run)
 
# The temporary PREFIX has a space in it, to prove the quoting holds up.
installcheck: ## Install into a temporary PREFIX, test that copy, then check uninstall leaves nothing
	$(Q)tmp=$$(mktemp -d) && trap 'rm -rf "$$tmp"' EXIT && \
	prefix="$$tmp/install root" && \
	$(say) INSTALL "$$prefix" && \
	$(MAKE) --no-print-directory install PREFIX="$$prefix" >/dev/null && \
	$(say) TEST "$$prefix/bin" && \
	GIT_WORKFLOW_BIN="$$prefix/bin" BATS_TEST_TIMEOUT=60 $(BATS) tests </dev/null && \
	$(say) UNINST "$$prefix" && \
	$(MAKE) --no-print-directory uninstall PREFIX="$$prefix" >/dev/null && \
	left=$$(find "$$prefix" -type f -o -type l) && \
	if [ -n "$$left" ]; then \
		printf 'error: uninstall left these behind:\n%s\n' "$$left" >&2; \
		exit 1; \
	fi
 
##@ Release
 
dist: ## Archive DIST_REF as DIST_NAME.tar.gz plus a sha256 file (the release workflow runs this)
	@$(say) ARCHIVE "$(DIST_NAME).tar.gz"
	$(Q)$(GIT) archive --format=tar.gz --prefix="$(DIST_NAME)/" -o "$(DIST_NAME).tar.gz" "$(DIST_REF)"
	@$(say) SHA256 "$(DIST_NAME).tar.gz.sha256"
	$(Q)if command -v sha256sum >/dev/null 2>&1; then \
		sha256sum "$(DIST_NAME).tar.gz"; \
	else \
		shasum -a 256 "$(DIST_NAME).tar.gz"; \
	fi >"$(DIST_NAME).tar.gz.sha256"
 
clean: ## Remove what dist wrote
	$(Q)for f in "$(DIST_NAME).tar.gz" "$(DIST_NAME).tar.gz.sha256"; do \
		if [ -e "$$f" ]; then $(say) RM "$$f"; $(RM) "$$f" || exit 1; fi; \
	done

