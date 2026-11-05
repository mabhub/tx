#!/usr/bin/env bash
# Checks the shell code printed by `tx init`, which runs in every interactive
# shell: bash keeps an EXIT trap set earlier, and evaluating the code twice
# (a re-sourced .bashrc) installs the exit hook only once.
# The generated code runs `tx notice`, so it runs on an isolated tmux server.
# Usage: tests/init.sh [path/to/tx]
set -u
TX=${1:-$(cd "$(dirname "$0")/.." && pwd)/tx}
export LC_ALL=C
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
start_test_server
export TX

fail=0
failed() { printf 'FAIL: %s\n' "$1"; fail=1; }

# Setting TMUX before the shell exits turns the reminder off: it would wait
# for an answer on the terminal. The previous trap holds a quote on purpose.
bash_code=$(cat <<'EOF'
trap 'echo "previous trap: it'\''s kept"' EXIT
eval "$("$TX" init bash)"
eval "$("$TX" init bash)"
trap -p EXIT
TMUX=x
EOF
)
# -i: the code only acts in interactive shells. Without a terminal, bash
# complains about job control on stderr.
out=$(bash --norc --noprofile -i -c "$bash_code" 2>/dev/null)
printf '%s\n' "$out"
[ "$(printf '%s\n' "$out" | grep -c "previous trap: it's kept")" -eq 1 ] \
  || failed "bash: the previous EXIT trap did not run exactly once"
case $out in *"trap -- '_tx_exit;"*) ;; *) failed "bash: tx's EXIT trap is not installed" ;; esac

if command -v zsh >/dev/null; then
  # shellcheck disable=SC2016 # expanded by the shell under test
  out=$(zsh -fi -c 'eval "$("$TX" init zsh)"; eval "$("$TX" init zsh)"; print -r -- "hooks: $zshexit_functions"; TMUX=x' 2>&1)
  printf '%s\n' "$out"
  [ "$out" = "hooks: _tx_exit" ] || failed "zsh: the exit hook should be installed once"
else
  echo "zsh not installed: zsh check skipped"
fi
[ $fail = 0 ] && echo OK
exit $fail
