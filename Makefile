# ==============================================================================
# git-workflow
#
# Plain Bash, so there is nothing to build. `make install` puts one program,
# git-workflow, in BINDIR (git runs it as `git workflow`), its libraries,
# commands and default alias sets in DATADIR, and the man pages and docs next
# to them. It writes DATADIR into the program. `make help` lists the targets
# and shows the configuration.
#
#   sudo make install                           system-wide, into /usr/local
#   make install PREFIX="$HOME/.local"          for your user only
#   make install PREFIX=/usr DESTDIR="$pkgdir"  staged, for a distro package
#   make aliases                                git b, git c, ... (your config)
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
# Everything but the program is sourced Bash or text, the same on every
# architecture, so it goes in share/ (lib/ is for architecture-dependent files).

DESTDIR ?=
PREFIX  ?= /usr/local
BINDIR  ?= $(PREFIX)/bin
DATADIR ?= $(PREFIX)/share/$(NAME)
DOCDIR  ?= $(PREFIX)/share/doc/$(NAME)
MANDIR  ?= $(PREFIX)/share/man
LINKDIR ?= $(HOME)/.local/bin

# Alias sets for `make aliases` / `make unaliases` (empty: install/uninstall defaults)
SETS ?=

# --- Files --------------------------------------------------------------------

PROGRAM  := bin/$(NAME)
LIBS     := $(wildcard share/*.sh) VERSION
COMMANDS := $(wildcard share/commands/*.sh)
ALIASES  := $(wildcard share/aliases/*)
MAN1     := $(wildcard man/*.1)
DOCS     := README.md CHANGELOG.md LICENSE

# What 1.x installed and 2.0 doesn't: the git-* commands, their libraries
# (in DATADIR since 1.4.2, in PREFIX/lib/git-workflow before), the alias file
# and their man pages. install and uninstall both clear them away, because
# git would run an old git-b in place of the new `b` alias.
OLD_COMMANDS := git-b git-c git-ps git-qc git-rb-pull git-sq git-sync
OLD_LIBS     := git-branch-utils.sh git-core-utils.sh git-release-utils.sh
OLD_LIBDIR   := $(PREFIX)/lib/$(NAME)
OLD_MAN1     := $(addsuffix .1,$(OLD_COMMANDS))

# `make dist` archives this ref under this name (the release workflow passes the tag)
DIST_REF  ?= HEAD
DIST_NAME ?= $(NAME)-$(VERSION)

# --- Guards -------------------------------------------------------------------
# Checked before any target runs. Paths are quoted everywhere, so spaces are fine.

# Only bash expands the ~ in PREFIX=~/.local. fish, zsh and sh pass it through,
# and the recipes would then create a directory literally named "~" in this one.
ifneq ($(findstring ~,$(DESTDIR)$(PREFIX)$(BINDIR)$(DATADIR)$(DOCDIR)$(MANDIR)$(LINKDIR)),)
  $(error A path contains a "~" that your shell did not expand. Use $$HOME instead: PREFIX="$$HOME/.local")
endif

# DATADIR is written into the installed program, which can run from any directory.
ifneq ($(patsubst /%,/,$(firstword $(DATADIR))),/)
  $(error DATADIR must be an absolute path, because the installed program uses it to find the rest. It is "$(DATADIR)")
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

# $(call remove_dir,DIR): remove DESTDIR/DIR once it's empty
remove_dir = d="$(DESTDIR)$(1)"; \
	if [ -d "$$d" ] && rmdir "$$d" 2>/dev/null; then $(say) RMDIR "$$d"; fi

# Clear away what 1.x installed in this PREFIX (see OLD_COMMANDS)
remove_1x = \
	$(call remove_files,$(BINDIR),$(OLD_COMMANDS)); \
	$(call remove_files,$(DATADIR),$(OLD_LIBS) $(NAME)-aliases); \
	$(call remove_files,$(OLD_LIBDIR),$(OLD_LIBS) VERSION); \
	$(call remove_files,$(MANDIR)/man1,$(OLD_MAN1)); \
	$(call remove_files,$(MANDIR)/man7,$(NAME).7); \
	$(call remove_dir,$(OLD_LIBDIR))

# Remove the symlink 1.x's `make link` left in LINKDIR
unlink_1x = for s in $(OLD_COMMANDS); do \
		l="$(LINKDIR)/$$s"; \
		if [ -L "$$l" ] && [ "$$(readlink "$$l")" = "$(CURDIR)/scripts/$$s" ]; then \
			$(say) RM "$$l"; \
			$(RM) "$$l" || exit 1 ; \
		fi; \
	done

# $(call path_note,DIR): after a real (unstaged) install into DIR, say when the
# program can't be found, or when another copy earlier on PATH runs instead
path_note = [ -n "$(DESTDIR)" ] || { \
		found=$$(command -v $(NAME) || true); \
		case $$found in \
		"$(1)/$(NAME)") ;; \
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
		DOCDIR  '$(DOCDIR)'  MANDIR  '$(MANDIR)' \
		LINKDIR '$(LINKDIR)' SETS    '$(or $(SETS),(defaults))'

##@ Install

install: all ## Install the program, its libraries and commands, the man pages and docs
	$(Q)$(remove_1x)
	$(Q)$(MKDIR_P) "$(DESTDIR)$(BINDIR)" "$(DESTDIR)$(DATADIR)/commands" \
		"$(DESTDIR)$(DATADIR)/aliases" "$(DESTDIR)$(DOCDIR)" "$(DESTDIR)$(MANDIR)/man1"
	$(Q)$(call install_files,$(DATADIR),$(INSTALL_DATA),$(LIBS))
	$(Q)$(call install_files,$(DATADIR)/commands,$(INSTALL_DATA),$(COMMANDS))
	$(Q)$(call install_files,$(DATADIR)/aliases,$(INSTALL_DATA),$(ALIASES))
	$(Q)$(call install_files,$(DOCDIR),$(INSTALL_DATA),$(DOCS))
	$(Q)$(call install_files,$(MANDIR)/man1,$(INSTALL_DATA),$(MAN1))
# The program last, so an interrupted install never leaves a program that
# can't find the rest. Its empty GIT_WORKFLOW_DATADIR= line (a checkout leaves
# it empty and looks in ../share) gets DATADIR. awk rather than sed: DATADIR
# comes in through the environment, so nothing in it needs escaping, and the
# exit status says whether the line was there exactly once.
	$(Q)stage=$$(mktemp -d) && trap 'rm -rf "$$stage"' EXIT && \
	DATADIR="$(DATADIR)" $(AWK) ' \
		$$0 == "GIT_WORKFLOW_DATADIR=" { print "GIT_WORKFLOW_DATADIR=\"" ENVIRON["DATADIR"] "\""; n++; next } \
		{ print } \
		END { exit (n != 1) }' "$(PROGRAM)" >"$$stage/$(NAME)" || { \
		echo "error: $(PROGRAM) needs exactly one empty GIT_WORKFLOW_DATADIR= line" >&2; \
		exit 1; \
	} && \
	$(say) INSTALL "$(DESTDIR)$(BINDIR)/$(NAME)" && \
	$(INSTALL_PROGRAM) "$$stage/$(NAME)" "$(DESTDIR)$(BINDIR)/$(NAME)"
	$(Q)$(call path_note,$(BINDIR))

uninstall: ## Remove what install put in PREFIX, and anything 1.x left there
	$(Q)[ -e "$(DESTDIR)$(BINDIR)/$(NAME)" ] || \
		echo "note: no $(NAME) in $(DESTDIR)$(BINDIR). Was it installed with another PREFIX?"
# The reverse of install: the program first, then what it uses
	$(Q)$(call remove_files,$(BINDIR),$(NAME))
	$(Q)$(call remove_files,$(DATADIR),$(notdir $(LIBS)))
	$(Q)$(call remove_files,$(DATADIR)/commands,$(notdir $(COMMANDS)))
	$(Q)$(call remove_files,$(DATADIR)/aliases,$(notdir $(ALIASES)))
	$(Q)$(call remove_files,$(DOCDIR),$(DOCS))
	$(Q)$(call remove_files,$(MANDIR)/man1,$(notdir $(MAN1)))
	$(Q)$(remove_1x)
# Only this project's own directories, and only once they're empty
	$(Q)$(call remove_dir,$(DATADIR)/commands); $(call remove_dir,$(DATADIR)/aliases); \
		$(call remove_dir,$(DATADIR)); $(call remove_dir,$(DOCDIR))
# Your alias sets are your config, so they stay; say how to drop them
	$(Q)[ -n "$(DESTDIR)" ] || \
		! $(GIT) config --global --get-all include.path 2>/dev/null | grep -q '/$(NAME)/aliases/' || \
		echo "note: ~/.gitconfig still includes your $(NAME) alias sets. make unaliases stops that."

aliases: ## Set up git b, git c, ... (SETS=extras for git lg, ...): git workflow aliases install
	$(Q)$(PROGRAM) aliases install $(SETS)

unaliases: ## Stop including the alias sets (your copies stay): git workflow aliases remove
	$(Q)$(PROGRAM) aliases remove $(SETS)

##@ Development

link: ## Symlink this checkout's program into LINKDIR, so edits take effect at once
	$(Q)$(MKDIR_P) "$(LINKDIR)"
	$(Q)$(unlink_1x)
	@$(say) LINK "$(LINKDIR)/$(NAME)"
	$(Q)ln -sfn "$(CURDIR)/$(PROGRAM)" "$(LINKDIR)/$(NAME)"
	$(Q)$(call path_note,$(LINKDIR))

unlink: ## Remove that symlink (only if it points into this checkout)
	$(Q)l="$(LINKDIR)/$(NAME)"; \
	if [ -L "$$l" ] && [ "$$(readlink "$$l")" = "$(CURDIR)/$(PROGRAM)" ]; then \
		$(say) RM "$$l"; \
		$(RM) "$$l"; \
	fi
	$(Q)$(unlink_1x)

lint: ## Shellcheck the program, libraries, commands and test helper; lint the man pages
	@$(say) LINT "$(PROGRAM) share/*.sh share/commands/*.sh"
	$(Q)$(SHELLCHECK) -x -P share $(PROGRAM) share/*.sh share/commands/*.sh
	@$(say) LINT tests/test_helper.bash
	$(Q)$(SHELLCHECK) -s bash tests/test_helper.bash
	$(Q)if command -v $(MANDOC) >/dev/null 2>&1; then \
		$(say) LINT "man/*"; \
		$(MANDOC) -Tlint -W warning $(MAN1); \
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
	left=$$(find "$$prefix" -type f -o -type l -o -name "*$(NAME)*") && \
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

