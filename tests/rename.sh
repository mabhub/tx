#!/usr/bin/env bash
# Checks that renaming a session starts from its current name: typed text is
# appended to it, accented letters included (the tests run in the C locale),
# and Enter on the unchanged name cancels quietly.
# Runs on an isolated tmux server (never touches your real sessions) and
# drives the numbered menu, with fzf hidden, inside a pty.
# Usage: tests/rename.sh [path/to/tx]
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

tmux new-session -d -s work bash --norc --noprofile

# The list reads "1) + new session  2) work", the session menu
# "1) Attach  2) Rename  3) Close". Rename work to work2 by typing "2" after
# the pre-filled name, then to work2é, then once more without changing it,
# and quit.
input=$'2\n2\n2\n2\n2\né\n2\n2\n\nq\n'
run_menu "$input" || failed "tx did not quit"
[ "$(tmux -u list-sessions -F '#{session_name}' 2>/dev/null)" = "work2é" ] \
  || failed "work was not renamed to work2, then work2é"
grep -q 'already exists' "$LOG" && failed "an unchanged name was not taken as cancel"
[ $fail = 0 ] || tr -d '\r' <"$LOG"
[ $fail = 0 ] && echo OK
exit $fail
