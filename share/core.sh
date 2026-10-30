# shellcheck shell=bash
# Sourced by every git-workflow command; not executable on its own.

# SPDX-License-Identifier: MIT
# SPDX-FileCopyrightText: 2026 Joshua Haveman
#
# This software is released under the MIT License, and is provided as is, without warranty.
# Modify & distribute freely.

# shellcheck disable=SC2034
# globals here are consumed by the scripts that source this file

# Include guard to prevent redundant parsing
if [ -n "${__WF_CORE_LOADED:-}" ]; then
    return 0
fi
__WF_CORE_LOADED=1

# OUTPUT HELPERS
if [ -t 2 ] && [ -z "${NO_COLOR:-}" ]; then
    __C_RED=$'\033[31m' __C_YEL=$'\033[33m' __C_BLU=$'\033[34m' __C_RST=$'\033[0m'
else
    __C_RED='' __C_YEL='' __C_BLU='' __C_RST=''
fi

info() { printf '%s\n' "$*" >&2; }
note() { printf '%s%s%s\n' "$__C_BLU" "$*" "$__C_RST" >&2; }
warn() { printf '%sWarning:%s %s\n' "$__C_YEL" "$__C_RST" "$*" >&2; }
err() { printf '%sError:%s %s\n' "$__C_RED" "$__C_RST" "$*" >&2; }

# ---------------------------------------------------------------------------
# Commands and the aliases that run them
# ---------------------------------------------------------------------------

# wf_resolve <name>: the command a name runs, short (1.x) names included.
# Prints nothing and fails for anything else.
wf_resolve() {
    case "$1" in
    branch | b) echo branch ;;
    commit | c) echo commit ;;
    quick-commit | qc) echo quick-commit ;;
    push | ps) echo push ;;
    squash | sq) echo squash ;;
    sync) echo sync ;;
    pull | rb-pull) echo pull ;;
    aliases) echo aliases ;;
    *) return 1 ;;
    esac
}

# Record an alias whose whole value is "workflow <command>"
__wf_note_alias() {
    local name="$1" w1 w2 rest cmd
    read -r w1 w2 rest <<<"$2"
    [ "$w1" = workflow ] && [ -n "$w2" ] && [ -z "$rest" ] || return 0
    cmd=$(wf_resolve "$w2") || return 0
    WF_ALIASES="$WF_ALIASES$cmd $name
"
}

# wf_alias_for <command>: the first alias that runs it, if any
wf_alias_for() {
    local cmd name
    while read -r cmd name; do
        if [ "$cmd" = "$1" ]; then
            printf '%s' "$name"
            return 0
        fi
    done <<<"$WF_ALIASES"
    return 1
}

# wf_cmd <command> [args...]: how to type a command, for messages. Uses your
# alias when you have one ("git ps force"), the full form otherwise
# ("git workflow push force").
wf_cmd() {
    local cmd="$1" name
    shift
    if name=$(wf_alias_for "$cmd"); then
        set -- "git $name" "$@"
    else
        set -- "git workflow $cmd" "$@"
    fi
    printf '%s' "$*"
}

# The installed version: next to the libraries when installed, at the root of
# a checkout otherwise
wf_version() {
    local f
    for f in "$GIT_WORKFLOW_DATADIR/VERSION" "$GIT_WORKFLOW_DATADIR/../VERSION"; do
        if [ -r "$f" ]; then
            cat "$f"
            return 0
        fi
    done
    echo unknown
}

# ---------------------------------------------------------------------------
# Configuration
#
# Every setting is a `workflow.*` key, read from these layers; a later layer
# wins:
#
#   1. defaults
#   2. the flow file: share/flows/<flow>, or ~/.config/git-workflow/flows/<flow>
#   3. what this repository looks like (its default branch, a next or develop branch)
#   4. your global git config (~/.gitconfig and what it includes)
#   5. the repository's committed .gitworkflow file (same format)
#   6. the repository's own git config (.git/config)
#   7. git -c workflow.<key>=<value>
#
# A key without a dot applies to the whole flow:
#
#   workflow.flow              gitflow | github | <your flow>    (default: detected)
#   workflow.mainBranch        production branch                  (default: the remote's default branch)
#   workflow.devBranch         integration branch; unset = mainBranch
#   workflow.integrate         pr | merge: how finish integrates a branch (default: pr)
#   workflow.releaseFromMain   true: `pre` and `release` tag main directly
#   workflow.remote            where your branches go (your fork, if you use one)
#   workflow.upstream          where mainBranch, devBranch and the tags live
#   workflow.forge             what opens pull requests (default: github, through gh)
#   workflow.prereleaseLabel   default label for `pre` (rc)
#   workflow.strict            true: flow violations abort instead of asking
#   workflow.versionFile       must match the version being tagged; "" disables.
#                              package.json, Cargo.toml and pyproject.toml are read
#                              as such; any other file holds just the version
#   workflow.tagPrefix         what comes before X.Y.Z in tags and branch names (v)
#   workflow.protected         extra protected branches (multi-valued)
#
# A key with a dot belongs to a branch type, workflow.<type>.<key>:
#
#   prefix      branch name prefix ("" for the type unprefixed branches belong to)
#   from        main | dev | latest-release: where `start` branches it from
#   into        main | dev | none: where `finish` integrates it (none: no such type)
#   integrate   pr | merge (default: workflow.integrate)
#   tag         none | merge | tip: tag <tagPrefix>X.Y.Z (named in the branch) on the merge
#               commit or on the branch's tested tip; anything but none makes the
#               type versioned
#   backMerge   none | dev: after merging into main, merge main into dev
#   single      true: one branch of this type open at a time
#
# A .gitworkflow file is someone else's: its values are data, checked against
# the lists above, and it can't set remote or upstream (they're about your
# clone). Flow files and .gitworkflow are read without includes.
# ---------------------------------------------------------------------------

# "<command> <alias>" lines, one per alias that runs a git-workflow command
# ("b = workflow branch"), so messages can name commands the way you type them
WF_ALIASES=''

# The resolved settings: "<key>\t<value>\t<source>" lines, later ones winning.
# Keys are lowercase: "devbranch", "release.prefix".
__WF_CONF=''
# Problems found while loading, warned about once the settings are resolved
__WF_PROBLEMS=''

__NL=$'\n' __TAB=$'\t'

# conf_get <key>: sets CONF_VAL and CONF_SRC from the last line for <key>;
# fails when no layer sets it. String operations only: it runs dozens of
# times per command, and a loop over a here-string makes a temp file each time.
conf_get() {
    local all="$__NL$__WF_CONF" after
    after="${all##*"$__NL$1$__TAB"}"
    if [ "$after" = "$all" ]; then
        CONF_VAL='' CONF_SRC=''
        return 1
    fi
    CONF_VAL="${after%%"$__TAB"*}"
    after="${after#*"$__TAB"}"
    CONF_SRC="${after%%"$__NL"*}"
}

# conf_all <key>: every value any layer sets (for multi-valued keys)
conf_all() {
    local line rest
    while IFS= read -r line; do
        [ "${line%%	*}" = "$1" ] || continue
        rest="${line#*	}"
        printf '%s\n' "${rest%	*}"
    done <<<"$__WF_CONF"
}

__wf_problem() {
    __WF_PROBLEMS="$__WF_PROBLEMS$1
"
}

# __wf_valid_branch <name>: a name git accepts for a branch (the rules of
# git-check-ref-format(1)), checked here: it runs for every setting on every
# command, and a git process each time adds up. Stricter only about "@".
__wf_valid_branch() {
    case "$1" in
    '' | @ | -* | /* | */ | *. | *..* | *@\{* | *//* | .* | */.* | *.lock | *.lock/*) return 1 ;;
    *[[:cntrl:]\ ~^:?*\[\\]*) return 1 ;;
    esac
    return 0
}

# __wf_name_ok <name>: lowercase letters, digits and '-', starting with a letter
# or digit. Spelled out, since [a-z] can match capitals in some locales.
__wf_name_ok() {
    case "$1" in
    '' | -* | *[!abcdefghijklmnopqrstuvwxyz0123456789-]*) return 1 ;;
    esac
}

# The flows you can pick: yours and the ones that ship
wf_flows() {
    local d f
    for d in "${XDG_CONFIG_HOME:-$HOME/.config}/git-workflow/flows" "$GIT_WORKFLOW_DATADIR/flows"; do
        for f in "$d"/*; do
            [ -f "$f" ] && basename "$f"
        done
    done | sort -u
}

# The keys each kind of source may set. Branch type keys are allowed wherever
# "type" is listed.
__WF_FLOW_KEYS=" description mainbranch devbranch integrate releasefrommain prereleaselabel versionfile tagprefix type "
__WF_REPO_KEYS=" flow$__WF_FLOW_KEYS strict protected forge "
__WF_GIT_KEYS="$__WF_REPO_KEYS remote upstream "
__WF_TYPE_KEYS=" prefix from into integrate tag backmerge single "

# __wf_add_line <layer var> <source> <git-config key> <value> <allowed keys>
# Normalizes a key read from a file or git config, checks it's one the source
# may set, and appends it to the layer. 2.x names still work.
__wf_add_line() {
    local layer="$1" src="$2" key="${3#workflow.}" value="$4" allowed="$5" type="" name key_ok=""
    case "$key" in
    releaseprefix) key=release.prefix ;;
    hotfixprefix) key=hotfix.prefix ;;
    finishtopic) key=topic.integrate ;;
    esac
    case "$key" in
    *.*)
        type="${key%%.*}"
        name="${key#*.}"
        if ! __wf_name_ok "$type"; then
            __wf_problem "workflow.$key ($src): a branch type is lowercase letters, digits and '-'; ignored."
            return 0
        fi
        case "$__WF_TYPE_KEYS" in
        *" $name "*) ;;
        *)
            __wf_problem "workflow.$key ($src) is not a setting git-workflow knows; ignored."
            return 0
            ;;
        esac
        case "$allowed" in
        *" type "*) ;;
        *)
            __wf_problem "workflow.$key can't be set in $src; ignored."
            return 0
            ;;
        esac
        ;;
    *)
        # "type" in the lists stands for the branch type keys; it isn't one
        case "$key" in
        type) ;;
        *) case "$__WF_GIT_KEYS" in *" $key "*) key_ok=1 ;; esac ;;
        esac
        case "$key_ok" in
        1) ;;
        *)
            __wf_problem "workflow.$key ($src) is not a setting git-workflow knows; ignored."
            return 0
            ;;
        esac
        case "$allowed" in
        *" $key "*) ;;
        *)
            __wf_problem "workflow.$key can't be set in $src; ignored."
            return 0
            ;;
        esac
        ;;
    esac
    # Tabs and newlines would break the store, and control characters have no
    # business in a setting (they could rewrite the terminal when printed)
    value="${value//[[:cntrl:]]/}"
    printf -v "$layer" '%s%s\t%s\t%s\n' "${!layer}" "$key" "$value" "$src"
}

# __wf_read_file <layer var> <source> <file> <allowed keys>
__wf_read_file() {
    local k v
    [ -f "$3" ] || return 0
    while read -r k v; do
        __wf_add_line "$1" "$2" "$k" "$v" "$4"
    done < <(git config --no-includes -f "$3" --get-regexp '^workflow\.' 2>/dev/null || true)
}

# Layers 4, 6 and 7 come from one `git config` call, sorted by its scopes;
# aliases are collected on the way
__L_GLOBAL='' __L_REPO='' __L_LOCAL='' __L_COMMAND='' __L_FLOW='' __L_DETECTED=''
__has_upstream=''
while IFS=$'\t' read -r __scope __rest; do
    __key="${__rest%% *}"
    __value=''
    [ "$__key" != "$__rest" ] && __value="${__rest#* }"
    case "$__key" in
    alias.*)
        __wf_note_alias "${__key#alias.}" "$__value"
        continue
        ;;
    remote.upstream.url)
        __has_upstream=1
        continue
        ;;
    esac
    case "$__scope" in
    local | worktree) __wf_add_line __L_LOCAL "git config" "$__key" "$__value" "$__WF_GIT_KEYS" ;;
    command) __wf_add_line __L_COMMAND "git -c" "$__key" "$__value" "$__WF_GIT_KEYS" ;;
    *) __wf_add_line __L_GLOBAL "global git config" "$__key" "$__value" "$__WF_GIT_KEYS" ;;
    esac
done < <(git config --show-scope --get-regexp '^(workflow|alias)\.|^remote\.upstream\.url$' 2>/dev/null || true)
unset __scope __rest __key __value

# Layer 5: the repository's .gitworkflow
WF_TOPLEVEL=$(git rev-parse --show-toplevel 2>/dev/null) || WF_TOPLEVEL=''
WF_REPO_FILE=''
if [ -n "$WF_TOPLEVEL" ] && [ -f "$WF_TOPLEVEL/.gitworkflow" ]; then
    WF_REPO_FILE="$WF_TOPLEVEL/.gitworkflow"
    __wf_read_file __L_REPO ".gitworkflow" "$WF_REPO_FILE" "$__WF_REPO_KEYS"
fi

# Your settings, without the flow yet: enough to pick the remotes and the flow
__WF_CONF="$__L_GLOBAL$__L_REPO$__L_LOCAL$__L_COMMAND"

REMOTE=origin
conf_get remote && [ -n "$CONF_VAL" ] && REMOTE="$CONF_VAL"
# The shared branches and the tags live on UPSTREAM; your branches go to
# REMOTE. They differ when you work from a fork: REMOTE is your fork, UPSTREAM
# the repository you send pull requests to.
UPSTREAM=''
conf_get upstream && UPSTREAM="$CONF_VAL"
if [ -z "$UPSTREAM" ]; then
    if [ -n "$__has_upstream" ]; then
        UPSTREAM=upstream
    else
        UPSTREAM="$REMOTE"
    fi
fi
unset __has_upstream
# __wf_remote_ok <key> <value>: a remote name, not something git would read
# as an option
__wf_remote_ok() {
    case "$2" in
    '' | -* | *[!ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789._-]*)
        __wf_problem "workflow.$1 '$2' is not a remote name; using origin."
        return 1
        ;;
    esac
}
__wf_remote_ok remote "$REMOTE" || REMOTE=origin
__wf_remote_ok upstream "$UPSTREAM" || UPSTREAM=origin

# Every ref the guesses below look at, from one git call: the next and develop
# branches (and a devBranch you set), here and on both remotes, and the
# remotes' HEADs (their default branch, recorded by clone)
__WF_REFS=''
if [ -n "$WF_TOPLEVEL" ]; then
    __names="next develop"
    conf_get devbranch && __wf_valid_branch "$CONF_VAL" && __names="$__names $CONF_VAL"
    __pats=''
    for __n in $__names; do
        __pats="$__pats refs/heads/$__n refs/remotes/$UPSTREAM/$__n refs/remotes/$REMOTE/$__n"
    done
    # shellcheck disable=SC2086 # a list of patterns
    __WF_REFS=$(git for-each-ref --format='%(refname) %(symref)' $__pats \
        "refs/remotes/$UPSTREAM/HEAD" "refs/remotes/$REMOTE/HEAD" 2>/dev/null) || __WF_REFS=''
    unset __names __pats __n
fi

# __wf_branch_exists <name>: here, or on either remote (from __WF_REFS)
__wf_branch_exists() {
    case "
$__WF_REFS" in
    *"
refs/heads/$1 "* | *"
refs/remotes/$UPSTREAM/$1 "* | *"
refs/remotes/$REMOTE/$1 "*) return 0 ;;
    esac
    return 1
}

# mainBranch: what you set, else the default branch the clone recorded
# (refs/remotes/<remote>/HEAD, e.g. master), else main
if conf_get mainbranch && [ -n "$CONF_VAL" ]; then
    __main="$CONF_VAL"
else
    __main=main
    for __r in "$UPSTREAM" "$REMOTE"; do
        while read -r __ref __target; do
            if [ "$__ref" = "refs/remotes/$__r/HEAD" ] && [ -n "$__target" ]; then
                __main="${__target#refs/remotes/"$__r"/}"
                __wf_add_line __L_DETECTED "the remote's default branch" mainbranch "$__main" " mainbranch "
                break 2
            fi
        done <<<"$__WF_REFS"
    done
    unset __r __ref __target
fi

# The flow: what you (or .gitworkflow) set, else a guess from the branches
WF_FLOW='' WF_FLOW_WHY=''
if conf_get flow && [ -n "$CONF_VAL" ]; then
    WF_FLOW="$CONF_VAL"
    WF_FLOW_WHY="$CONF_SRC"
elif conf_get devbranch && [ -n "$CONF_VAL" ] && [ "$CONF_VAL" = "$__main" ]; then
    # 2.x's way to ask for trunk / GitHub flow
    WF_FLOW=github WF_FLOW_WHY="workflow.devBranch is mainBranch"
elif conf_get devbranch && [ -n "$CONF_VAL" ] && __wf_branch_exists "$CONF_VAL"; then
    WF_FLOW=gitflow WF_FLOW_WHY="workflow.devBranch"
elif __wf_branch_exists next; then
    WF_FLOW=gitflow WF_FLOW_WHY="guessed: there's a 'next' branch"
elif __wf_branch_exists develop; then
    WF_FLOW=gitflow WF_FLOW_WHY="guessed: there's a 'develop' branch"
else
    WF_FLOW=github WF_FLOW_WHY="guessed: no 'next' or 'develop' branch"
fi

# The flow file: yours first, then the ones that ship
WF_FLOW_FILE=''
if __wf_name_ok "$WF_FLOW"; then
    for __f in "${XDG_CONFIG_HOME:-$HOME/.config}/git-workflow/flows/$WF_FLOW" \
        "$GIT_WORKFLOW_DATADIR/flows/$WF_FLOW"; do
        if [ -f "$__f" ]; then
            WF_FLOW_FILE="$__f"
            break
        fi
    done
    unset __f
fi
if [ -z "$WF_FLOW_FILE" ]; then
    __wf_problem "there's no flow named '$WF_FLOW' (workflow.flow, $WF_FLOW_WHY); using github. The flows: $(wf_flows | tr '\n' ' ')"
    WF_FLOW=github WF_FLOW_WHY="workflow.flow was unknown"
    WF_FLOW_FILE="$GIT_WORKFLOW_DATADIR/flows/github"
fi
__wf_read_file __L_FLOW "flow $WF_FLOW" "$WF_FLOW_FILE" "$__WF_FLOW_KEYS"

# A git flow repository whose dev branch is develop, not next: use develop,
# unless you set devBranch
if ! conf_get devbranch; then
    __user_conf="$__WF_CONF"
    __WF_CONF="$__L_FLOW"
    if conf_get devbranch && [ "$CONF_VAL" = next ] && ! __wf_branch_exists next &&
        __wf_branch_exists develop; then
        __wf_add_line __L_DETECTED "the 'develop' branch" devbranch develop " devbranch "
    fi
    __WF_CONF="$__user_conf"
    unset __user_conf
fi

__L_DEFAULT='' # nothing to read: conf_get falls back to the defaults below
__WF_CONF="$__L_DEFAULT$__L_FLOW$__L_DETECTED$__L_GLOBAL$__L_REPO$__L_LOCAL$__L_COMMAND"
unset __L_DEFAULT __L_FLOW __L_DETECTED __L_GLOBAL __L_REPO __L_LOCAL __L_COMMAND __main

# __wf_bool <key> <default>: sets the named variable to true or false
__wf_bool() {
    local var="$1" key="$2" value="$3"
    if conf_get "$key"; then
        case "$CONF_VAL" in
        '' | [Tt][Rr][Uu][Ee] | [Yy][Ee][Ss] | [Oo][Nn] | 1) value=true ;;
        [Ff][Aa][Ll][Ss][Ee] | [Nn][Oo] | [Oo][Ff][Ff] | 0) value=false ;;
        *) __wf_problem "workflow.$key ($CONF_SRC) must be true or false, not '$CONF_VAL'; using $value." ;;
        esac
    fi
    printf -v "$var" '%s' "$value"
}

MAIN_BRANCH=main
if conf_get mainbranch && [ -n "$CONF_VAL" ]; then
    if __wf_valid_branch "$CONF_VAL"; then
        MAIN_BRANCH="$CONF_VAL"
    else
        __wf_problem "workflow.mainBranch ($CONF_SRC) '$CONF_VAL' is not a valid branch name; using main."
    fi
fi
DEV_BRANCH="$MAIN_BRANCH"
if conf_get devbranch && [ -n "$CONF_VAL" ]; then
    if __wf_valid_branch "$CONF_VAL"; then
        DEV_BRANCH="$CONF_VAL"
    else
        __wf_problem "workflow.devBranch ($CONF_SRC) '$CONF_VAL' is not a valid branch name; using $MAIN_BRANCH."
    fi
fi

INTEGRATE="pr"
if conf_get integrate; then
    case "$CONF_VAL" in
    pr | merge) INTEGRATE="$CONF_VAL" ;;
    *) __wf_problem "workflow.integrate ($CONF_SRC) must be pr or merge, not '$CONF_VAL'; using pr." ;;
    esac
fi

PRERELEASE_LABEL=rc
if conf_get prereleaselabel; then
    case "$CONF_VAL" in
    '' | *[!0-9A-Za-z-]*) __wf_problem "workflow.prereleaseLabel ($CONF_SRC) must be letters, digits and '-'; using rc." ;;
    *) PRERELEASE_LABEL="$CONF_VAL" ;;
    esac
fi

VERSION_FILE=VERSION
if conf_get versionfile; then
    # A path in the repository: `start` may write to it, and .gitworkflow is
    # someone else's file
    case "/$CONF_VAL/" in
    //*/ | */../* | */-*)
        __wf_problem "workflow.versionFile ($CONF_SRC) '$CONF_VAL' must be a path inside the repository; using VERSION."
        ;;
    *) VERSION_FILE="$CONF_VAL" ;;
    esac
fi

# Versions are <tagPrefix>X.Y.Z, in tags and in branch names (release/v1.2.3).
# "" for 1.2.3, or a path for one package of several (pkg/v1.2.3).
TAG_PREFIX=v
if conf_get tagprefix; then
    if [ -z "$CONF_VAL" ] || __wf_valid_branch "${CONF_VAL}1.0.0"; then
        TAG_PREFIX="$CONF_VAL"
    else
        __wf_problem "workflow.tagPrefix ($CONF_SRC) '$CONF_VAL' can't start a tag name; using v."
    fi
fi
# How a version looks, for messages: vX.Y.Z, and an example, v1.2.3
VFMT="${TAG_PREFIX}X.Y.Z" VEX="${TAG_PREFIX}1.2.3"

FORGE=github
if conf_get forge; then
    if ! __wf_name_ok "$CONF_VAL"; then
        __wf_problem "workflow.forge ($CONF_SRC) '$CONF_VAL' is not a forge name; using github."
    elif [ -f "$GIT_WORKFLOW_DATADIR/forges/$CONF_VAL.sh" ]; then
        FORGE="$CONF_VAL"
    else
        __wf_problem "workflow.forge ($CONF_SRC): git-workflow has no forge '$CONF_VAL'; using github."
    fi
fi

__wf_bool STRICT strict false
__wf_bool RELEASE_FROM_MAIN releasefrommain false

EXTRA_PROTECTED=''
while IFS= read -r __p; do
    [ -n "$__p" ] || continue
    if __wf_valid_branch "$__p"; then
        EXTRA_PROTECTED="$EXTRA_PROTECTED $__p"
    else
        __wf_problem "workflow.protected '$__p' is not a valid branch name; ignored."
    fi
done < <(conf_all protected)
unset __p

# ---------------------------------------------------------------------------
# Branch types
#
# WF_TYPES lists them in the order they were first defined. Each one's settings
# are resolved and checked once, into __WFT_<type>_<key> variables (a '-' in
# the type's name becomes '_', which type names can't contain).
# ---------------------------------------------------------------------------
WF_TYPES=''

__wf_enum() { # <value> <allowed...>: true if value is one of them
    local v="$1"
    shift
    case " $* " in
    *" $v "*) return 0 ;;
    esac
    return 1
}

# __wf_type_key <type> <key> <default> <allowed values, or "">: sets TV
__wf_type_key() {
    TV="$3"
    conf_get "$1.$2" || return 0
    # shellcheck disable=SC2086 # $4 is a list
    if [ -n "$4" ] && ! __wf_enum "$CONF_VAL" $4; then
        __wf_problem "workflow.$1.$2 ($CONF_SRC) must be one of: $4; not '$CONF_VAL'. Using $3."
        return 0
    fi
    TV="$CONF_VAL"
}

__wf_load_types() {
    local line key type seen=" " prefix from into integrate tag back single empty="" prefixes=" "
    while IFS= read -r line; do
        key="${line%%	*}"
        case "$key" in
        *.*) type="${key%%.*}" ;;
        *) continue ;;
        esac
        case "$seen" in
        *" $type "*) continue ;;
        esac
        seen="$seen$type "

        __wf_type_key "$type" into none "main dev none"
        into="$TV"
        if ! conf_get "$type.into"; then
            # Your global config covers every repository, including ones whose
            # flow has no such type (2.x's releasePrefix in GitHub flow): quietly
            case "$line" in
            *"	global git config") ;;
            *) __wf_problem "branch type '$type' has no workflow.$type.into, so it isn't one; ignored." ;;
            esac
            continue
        fi
        [ "$into" = none ] && continue

        __wf_type_key "$type" prefix '' ''
        prefix="$TV"
        if [ -n "$prefix" ] && ! __wf_valid_branch "${prefix}x"; then
            __wf_problem "workflow.$type.prefix ($CONF_SRC) '$prefix' can't start a branch name; ignored the '$type' type."
            continue
        fi
        if [ -z "$prefix" ]; then
            if [ -n "$empty" ]; then
                __wf_problem "branch types '$empty' and '$type' both have no prefix; ignored '$type'."
                continue
            fi
            empty="$type"
        else
            case "$prefixes" in
            *" $prefix "*)
                __wf_problem "two branch types use the prefix '$prefix'; ignored '$type'."
                continue
                ;;
            esac
            prefixes="$prefixes$prefix "
        fi
        __wf_type_key "$type" from dev "main dev latest-release"
        from="$TV"
        __wf_type_key "$type" integrate "$INTEGRATE" "pr merge"
        integrate="$TV"
        __wf_type_key "$type" tag none "none merge tip"
        tag="$TV"
        __wf_type_key "$type" backmerge none "none dev"
        back="$TV"
        __wf_bool single "$type.single" false

        WF_TYPES="$WF_TYPES $type"
        line="__WFT_${type//-/_}"
        printf -v "${line}_prefix" '%s' "$prefix"
        printf -v "${line}_from" '%s' "$from"
        printf -v "${line}_into" '%s' "$into"
        printf -v "${line}_integrate" '%s' "$integrate"
        printf -v "${line}_tag" '%s' "$tag"
        printf -v "${line}_back" '%s' "$back"
        printf -v "${line}_single" '%s' "$single"
    done <<<"$__WF_CONF"
    WF_TYPES="${WF_TYPES# }"
}
__wf_load_types

# type_get <type>: sets T_PREFIX T_FROM T_INTO T_INTEGRATE T_TAG T_BACK T_SINGLE;
# fails for a type this flow doesn't have
type_get() {
    local v
    case " $WF_TYPES " in
    *" $1 "*) ;;
    *) return 1 ;;
    esac
    v="__WFT_${1//-/_}_prefix" && T_PREFIX="${!v}"
    v="__WFT_${1//-/_}_from" && T_FROM="${!v}"
    v="__WFT_${1//-/_}_into" && T_INTO="${!v}"
    v="__WFT_${1//-/_}_integrate" && T_INTEGRATE="${!v}"
    v="__WFT_${1//-/_}_tag" && T_TAG="${!v}"
    v="__WFT_${1//-/_}_back" && T_BACK="${!v}"
    v="__WFT_${1//-/_}_single" && T_SINGLE="${!v}"
}

# branch_type <branch>: the type a branch belongs to, by the longest prefix
# that matches, else the type without a prefix. main and dev match that one
# too, so callers rule out protected branches first.
branch_type() {
    local t best="" best_len=-1
    for t in $WF_TYPES; do
        type_get "$t"
        case "$1" in
        "$T_PREFIX"*)
            if [ "${#T_PREFIX}" -gt "$best_len" ]; then
                best="$t" best_len="${#T_PREFIX}"
            fi
            ;;
        esac
    done
    printf '%s' "$best"
}

# Type is versioned: its branches are named <tagPrefix>X.Y.Z and finish with a tag
type_versioned() {
    type_get "$1" && [ "$T_TAG" != none ]
}

# resolve_point <main|dev>: the branch it names
resolve_point() {
    case "$1" in
    main) printf '%s' "$MAIN_BRANCH" ;;
    dev) printf '%s' "$DEV_BRANCH" ;;
    esac
}

# Say what's wrong with the settings, once per command
if [ -n "$__WF_PROBLEMS" ]; then
    while IFS= read -r __line; do
        [ -n "$__line" ] && warn "$__line"
    done <<<"$__WF_PROBLEMS"
    unset __line
fi

# Functions
get_working_branch() {
    git symbolic-ref --short HEAD 2>/dev/null || echo ''
}

working_branch=$(get_working_branch) || :

require_branch() {
    if [ -z "$working_branch" ]; then
        err "not on a branch (detached HEAD). Switch to a branch first."
        return 1
    fi
}

get_user_input() {
    local user_input="${1:-}"
    local prompt_msg="${2:-}"
    REPLY=""
    if [ -z "$user_input" ]; then
        while true; do
            read -r -p "$prompt_msg " REPLY || return 1
            if [ -n "$REPLY" ]; then
                break
            fi
        done
    else
        REPLY="$user_input"
        return 0
    fi
}

# -y/--yes (start, pre, release, finish): answer the command's questions
# with yes. Flow warnings still ask, or abort in strict mode: -y means "I
# meant to do this", not "skip the guardrails".
ASSUME_YES=''

# yes or no
yes_no() {
    local yn_message="${1:-"Null"}"
    local yn_default="${2:-n}"
    local yn_options

    case "$yn_default" in
    [yY] | [yY][eE][sS])
        yn_options="[Y/n]"
        yn_default="y"
        ;;
    *)
        yn_options="[y/N]"
        yn_default="n"
        ;;
    esac
    # flow_warn sets __wf_ask_anyway, so -y never answers a flow warning
    if [ -n "$ASSUME_YES" ] && [ -z "${__wf_ask_anyway:-}" ]; then
        info "$yn_message $yn_options: y (-y)"
        REPLY=y
        return 0
    fi
    while :; do
        # End of input (Ctrl-D, or no terminal) declines; the caller says
        # what was aborted, so only end the prompt's line here
        if ! read -r -p "$yn_message $yn_options: " REPLY; then
            printf '\n' >&2
            return 1
        fi

        if [ -z "$REPLY" ]; then
            REPLY="$yn_default"
        fi

        case "$REPLY" in
        [yY] | [yY][eE][sS])
            return 0
            ;;
        [nN] | [nN][oO])
            return 1
            ;;
        *)
            printf 'Invalid choice.\n' >&2
            ;;
        esac
    done
}

# Flow violations: abort in strict mode, otherwise, warn and ask.
# Returns 0 to continue and 1 to abort
flow_warn() {
    local __wf_ask_anyway=1
    warn "$1"
    if [ "$STRICT" = "true" ]; then
        err "aborting (workflow.strict is enabled)."
        return 1
    fi
    yes_no "Continue anyway?" || {
        info "Aborted."
        return 1
    }
}

is_protected_branch() {
    local branch="$1" p
    for p in "$MAIN_BRANCH" "$DEV_BRANCH" $EXTRA_PROTECTED; do
        [ "$branch" = "$p" ] && return 0
    done
    return 1
}

# True when <branch> only takes changes through pull requests: some branch
# type finishes into it with integrate=pr
pr_only_branch() {
    local t
    for t in $WF_TYPES; do
        type_get "$t"
        if [ "$T_INTEGRATE" = pr ] && [ "$(resolve_point "$T_INTO")" = "$1" ]; then
            return 0
        fi
    done
    return 1
}

# The remote a branch lives on: the shared (protected) ones on UPSTREAM, yours
# on REMOTE
remote_for() {
    if is_protected_branch "$1"; then
        printf '%s' "$UPSTREAM"
    else
        printf '%s' "$REMOTE"
    fi
}

# <remote>/<branch>: the remote-tracking copy of a branch
remote_ref() {
    printf '%s/%s' "$(remote_for "$1")" "$1"
}

# host/owner/repo of a GitHub-style remote, from its configured URL
# (github.com/joshua-hvmn/git-workflow); empty otherwise
remote_slug() {
    local url host
    url=$(git config --get "remote.$1.url") || return 0
    url="${url%/}"
    url="${url%.git}"
    case "$url" in
    git@*:*) url="${url#git@}" && host="${url%%:*}" && url="${url#*:}" ;;
    ssh://git@*/*) url="${url#ssh://git@}" && host="${url%%/*}" && url="${url#*/}" ;;
    https://*/*/*) url="${url#https://}" && host="${url%%/*}" && url="${url#*/}" ;;
    *) return 0 ;;
    esac
    host="${host#*@}" # https://user@host
    host="${host%:*}" # ssh://git@host:22
    printf '%s/%s' "$host" "$url"
}

# detect protected branch
# - pass "commit", "push", "del_branch" or "fin_branch"
detect_protected_branch() {
    local type_msg="${1:-}"
    local current_branch="${2:-$working_branch}"

    is_protected_branch "$current_branch" || return 0

    case "$type_msg" in
    push)
        if pr_only_branch "$current_branch"; then
            err "'$current_branch' takes changes through pull requests; pushing to it would skip review, or be rejected."
            info "Move your commits to a branch and open a pull request from there:"
            info "  git switch -c <name> && git branch -f $current_branch $(remote_ref "$current_branch") && $(wf_cmd branch finish)"
            return 1
        fi
        ;;
    del_branch)
        err "you cannot delete protected branch '$current_branch'."
        return 1
        ;;
    fin_branch)
        err "you cannot finish protected branch '$current_branch'."
        return 1
        ;;
    esac
    flow_warn "'$current_branch' is a protected branch; you are about to $type_msg directly on it."
}

# check for staged files
check_files_staged() {
    if git diff --cached --quiet --; then
        info "No files are staged for commit."
        git status -sb
        if yes_no "Stage all tracked and untracked files now?" "y"; then
            git add -A
            # check for staged files again to make sure
            if git diff --cached --quiet --; then
                err "working tree is clean. Nothing to stage."
                return 1
            fi
        else
            info "Commit aborted."
            return 1
        fi
    fi
    return 0
}

# enter commit message
commit_message_check() {
    REPLY="${1:-}"

    while :; do
        case "$REPLY" in
        *[![:space:]]*) break ;;
        esac

        if ! read -r -p "Enter a commit message: " REPLY; then
            printf '\nCommit aborted.\n' >&2
            return 1
        fi
    done
}
commit_pre_checks() {
    local mode="${1:-}"
    shift

    if [ "$mode" != "amend" ]; then
        check_files_staged || return 1
    fi
    commit_message_check "$@" || return 1
}
# commit_changes [--amend] [--] [message words...]
# The message is plain words, so anything else starting with "-" is almost
# certainly a `git commit` flag typed from habit: `git c -m "fix"` (the alias) would
# otherwise commit the message "-m fix". Put -- before a message that really
# starts with a dash.
commit_changes() {
    local amend=""

    if [ "${1:-}" = "--amend" ]; then
        amend=1
        shift
    fi
    if [ "${1:-}" = "--" ]; then
        shift
    else
        case "${1:-}" in
        -*)
            err "unknown option '$1'. The message is plain words: $(wf_cmd commit fix the bug), or $(wf_cmd quick-commit "'fix the bug'")"
            info "(use --): $(wf_cmd commit "[--amend] -- $1")"
            return 1
            ;;
        esac
    fi

    if [ -n "$amend" ]; then
        if [ "$#" -eq 0 ]; then
            git commit --amend --no-edit
            return
        fi
        commit_pre_checks "amend" "$*" || return 1
        git commit --amend -m "$REPLY"
        return
    fi
    commit_pre_checks "normal" "$*" || return 1
    git commit -m "$REPLY"
}

# ---------------------------------------------------------------------------
# Remote state
#
# Each fetch/ls-remote/pull/push is a separate SSH connection to the remote,
# which is where nearly all the time goes. So: fetch once per command
# (sync_remote), then answer every "does it exist on the remote?" question
# from the local remote-tracking refs instead of asking the network again.
# ---------------------------------------------------------------------------
__SYNCED=0

sync_remote() {
    [ "$__SYNCED" -eq 1 ] && return 0
    __SYNCED=1
    # --tags also fetches all tags; --prune drops deleted remote branches
    # (it does not delete local-only tags). Tags come from UPSTREAM: a fork's
    # copies of them are left alone.
    git fetch --quiet --prune --tags "$UPSTREAM" ||
        warn "could not fetch from '$UPSTREAM'; using the last known remote state."
    if [ "$REMOTE" != "$UPSTREAM" ]; then
        git fetch --quiet --prune --no-tags "$REMOTE" ||
            warn "could not fetch from '$REMOTE'; using the last known remote state."
    fi
}

# Answered locally from refs/remotes/<remote>/*; call sync_remote first for fresh data.
remote_branch_exists() {
    git show-ref --verify --quiet "refs/remotes/$(remote_ref "$1")"
}

# git workflow pull: switch to a branch and bring it up to date with the remote
pull_branch() {
    local current="${1:-$working_branch}" rref
    if [ -z "$current" ]; then
        err "Not on a branch."
        return 1
    fi

    sync_remote

    if [ "$(get_working_branch)" != "$current" ]; then
        git switch "$current" || return 1
    fi

    remote_branch_exists "$current" || return 0
    rref=$(remote_ref "$current")

    if is_protected_branch "$current"; then
        # main/next should never have local-only commits. A rebase here would
        # flatten any unpushed merge commits (e.g. after a failed finish), so
        # only fast-forward, and stop if the branch has diverged.
        git merge --ff-only "$rref" || {
            err "local '$current' has diverged from '$rref'; resolve it by hand."
            return 1
        }
    else
        git merge-base --is-ancestor "refs/remotes/$rref" "refs/heads/$current" && return 0
        if history_rewritten "$current"; then
            err "'$current' was rewritten after it was pushed."
            info "Pulling would replay the old commits on top. Publish the rewrite first: $(wf_cmd push force)"
            return 1
        fi
        git rebase --autostash "$rref"
    fi
}

pull_current_branch() {
    sync_remote
    if remote_branch_exists "$working_branch"; then
        info "Branch exists on remote. Syncing..."
        pull_branch "$working_branch"
    fi
}

# True when <branch> has diverged from its remote copy only because it was
# rewritten locally (squash, rebase, amend) after being pushed: the remote tip
# is a commit this branch pointed at before, according to its reflog. Pulling
# would then replay the old commits on top of the rewritten ones.
# (This is the same test `git push --force-if-includes` uses.)
history_rewritten() {
    local branch="$1" tip entries

    remote_branch_exists "$branch" || return 1
    tip=$(git rev-parse "refs/remotes/$(remote_ref "$branch")") || return 1
    # Remote is behind or equal: an ordinary push
    git merge-base --is-ancestor "$tip" "refs/heads/$branch" && return 1

    entries=$(git rev-list --walk-reflogs --max-count=200 "refs/heads/$branch" 2>/dev/null) || return 1
    [ -n "$entries" ] || return 1
    # Prints the tip if no reflog entry contains it
    # shellcheck disable=SC2086
    [ -z "$(git rev-list --max-count=1 "$tip" --not $entries)" ]
}
