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

zmodload zsh/zpty zsh/zselect || exit 1
local dir=$1 matches=$2 line=$3 dump=${2:h}/zcompdump out i
rm -f "$matches" "$matches.done"
zpty z zsh -f -i
zpty -w z "PS1=''; fpath=(${(q)dir} \$fpath); autoload -Uz compinit; compinit -u -C -d ${(q)dump}"
zpty -w z "_record() { compadd() { builtin compadd -O __m \"\$@\"; print -rl -- \"\${^__m[@]}\" >>| ${(q)matches}; builtin compadd \"\$@\"; }; _main_complete; unfunction compadd; : >| ${(q)matches}.done; }"
zpty -w z 'zle -C record-matches complete-word _record; bindkey "^T" record-matches; echo SET""UP-DONE'
zpty -r -m z out '*SETUP-DONE*' || exit 1
zpty -w -n z "$line"$'\x14'
# Wait for the completion to finish (the widget writes <matches file>.done),
# checking every 10 ms, for at most 20 seconds: tests run in parallel, and a
# busy machine can take a while to start zsh and its completion
for i in {1..2000}; do
    [[ -e $matches.done ]] && break
    zselect -t 1
done
zpty -d z
[[ -f $matches ]] && sort -u "$matches"
