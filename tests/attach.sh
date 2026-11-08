#!/usr/bin/env bash
# Checks that attaching to a session that vanished after the list was shown
# brings tx back to the list with a message, instead of stopping on tmux's
# error.
# Runs on an isolated tmux server (never touches your real sessions) and
# drives the numbered menu, with fzf hidden, inside a pty.
# Usage: tests/attach.sh [path/to/tx]
set -u
TX=${1:-$(cd "$(dirname "$0")/.." && pwd)/tx}
export LC_ALL=C
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
start_test_server
LOG=$TMUX_TMPDIR/menu.log
# A PATH without fzf: tx falls back to its numbered menu, which reads stdin.
SANDBOX=$(mktemp -d /tmp/txb.XXXX) || exit 1
no_fzf_path "$SANDBOX"

fail=0
failed() { printf 'FAIL: %s\n' "$1"; fail=1; }

tmux new-session -d -s gone bash --norc --noprofile
tmux new-session -d -s work bash --norc --noprofile  # keeps the server up

# Kill gone once tx has listed it, before run_menu types (after 2 s).
{
  for _ in $(seq 40); do grep -q work "$LOG" 2>/dev/null && break; sleep 0.05; done
  tmux kill-session -t =gone
} &

# The list reads "1) + new session  2) gone  3) work", the session menu
# "1) Attach  2) Rename  3) Close". Attach to gone, then quit from the list.
input=$'2\n1\nq\n'
run_menu "$input" || failed "tx did not quit"
grep -q 'no longer exists' "$LOG" || failed "the vanished session was not reported"
grep -q "can't find session" "$LOG" && failed "tx stopped on tmux's error"
[ $fail = 0 ] || tr -d '\r' <"$LOG"
[ $fail = 0 ] && echo OK
exit $fail
