# zsh -f zsh_complete.zsh <completion dir> <matches file> <line>
#
# Prints the matches zsh's own completion offers at the end of <line>, as an
# interactive zsh would: it runs one on a pseudo-terminal (zsh/zpty), with
# compinit and <completion dir> on $fpath, types <line>, then a key bound
# to completion, and records every match compadd adds to <matches file>.
#
# compinit's dump file is kept beside <matches file>: a test's first call
# writes it, and the rest skip compinit's scan of every function on $fpath,
# which is nearly all of what a call costs.
#
# Nothing waits without a limit, so a zsh that misbehaves fails the test with
# what its terminal showed, instead of hanging it. The zsh says through files
# when its line editor is reading and when the completion is done, and its
# output is read as it comes: a terminal nobody reads stops the program
# writing to it once its buffer fills.

zmodload zsh/zpty zsh/zselect || exit 1
local dir=$1 matches=$2 line=$3 dump=${2:h}/zcompdump screen="" chunk

# wait_for <file> <what it means if it never comes>: read zsh's output until
# <file> exists, checking every 10 ms, for at most 15 seconds (tests run in
# parallel, and a busy machine can take a while to start zsh and compinit)
wait_for() {
    local i
    for i in {1..1500}; do
        while zpty -r -t z chunk; do screen+=$chunk; done
        [[ -e $1 ]] && return 0
        zselect -t 1
    done
    print -r -- "zsh_complete: $2 within 15 seconds; zsh's terminal showed:" >&2
    print -r -- "${screen//$'\r'/}" >&2
    zpty -d z
    exit 1
}

rm -f "$matches" "$matches".{ready,done}
zpty z zsh -f -i
zpty -w z "PS1=''; unsetopt auto_list beep; fpath=(${(q)dir} \$fpath); autoload -Uz compinit; compinit -u -C -d ${(q)dump}"
zpty -w z "_record() { compadd() { builtin compadd -O __m \"\$@\"; print -rl -- \"\${^__m[@]}\" >>| ${(q)matches}; builtin compadd \"\$@\"; }; _main_complete; unfunction compadd; : >| ${(q)matches}.done; }"
# The key is ^G, which no terminal takes for itself (macOS's takes ^T for its
# status line), and zle-line-init says when the line editor is reading
zpty -w z "zle -C record-matches complete-word _record; bindkey '^G' record-matches; zle-line-init() { : >| ${(q)matches}.ready; }; zle -N zle-line-init"
wait_for "$matches.ready" "the line editor never started"
zpty -w -n z "$line"$'\a'
wait_for "$matches.done" "the completion never finished"
zpty -d z
[[ -f $matches ]] && sort -u "$matches"
