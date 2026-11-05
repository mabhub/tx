#!/usr/bin/env bash
# Checks that closing a session from the menu only types into idle shells:
# a pane running another program, or a script (which tmux names "bash" like
# a shell), must survive, without "exit" in its input.
# Runs on an isolated tmux server (never touches your real sessions) and
# drives the numbered menu, with fzf hidden, inside a pty.
# Usage: tests/close.sh [path/to/tx]
set -u
TX=${1:-$(cd "$(dirname "$0")/.." && pwd)/tx}
# Short socket path: Unix sockets are limited to about 100 characters.
TMUX_TMPDIR=$(mktemp -d /tmp/txt.XXXX); export TMUX_TMPDIR
unset TMUX; export LC_ALL=C TERM=${TERM:-xterm}
[ "$TERM" = dumb ] && export TERM=xterm
LOG=$TMUX_TMPDIR/menu.log

# A PATH without fzf: tx falls back to its numbered menu, which reads stdin.
SANDBOX=$(mktemp -d /tmp/txb.XXXX)
for t in bash tmux; do ln -s "$(command -v "$t")" "$SANDBOX/$t"; done
for f in /bin/* /usr/bin/*; do
  [ "${f##*/}" = fzf ] || ln -s "$f" "$SANDBOX/" 2>/dev/null
done

pty() { # pty CMD: runs CMD in a new pty (Linux and BSD script syntaxes)
  case $(uname -s) in
    Linux) script -qfc "$(printf '%q' "$1")" /dev/null ;;
    *)     script -q /dev/null "$1" ;;
  esac
}

shell=(bash --norc --noprofile)
job='sleep 600; : tx-test-job'  # a script, which tmux shows as "bash"
tmux new-session -d -s idle "${shell[@]}"
tmux new-session -d -s busy "${shell[@]}"
# "exit" typed into cat would show up in the pane.
cat_pane=$(tmux split-window -d -P -F '#{pane_id}' -t =busy: cat)
tmux split-window -d -t =busy: bash -c "$job"  # the pane's own command
job_pane=$(tmux split-window -d -P -F '#{pane_id}' -t =busy: "${shell[@]}")
tmux send-keys -t "$job_pane" "bash -c '$job'" Enter  # started from a prompt
sleep 0.5

# The list reads "1) + new session  2) busy  3) idle", the session menu
# "1) Attach  2) Rename  3) Close". Close idle, then busy, decline the
# kill-session offered for the panes left in busy, and quit.
input=$'3\n3\ny\n2\n3\ny\nn\nq\n'
# exec: the job's PID becomes this sleep, so the final kill stops it too.
{ sleep 2; printf '%s' "$input"; exec sleep 30; } | PATH=$SANDBOX pty "$TX" >"$LOG" 2>&1 &
pid=$!
for _ in $(seq 40); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done

fail=0
failed() { printf 'FAIL: %s\n' "$1"; fail=1; }
kill -0 "$pid" 2>/dev/null && failed "tx did not quit"
tmux has-session -t =idle 2>/dev/null && failed "idle session still open"
tmux has-session -t =busy 2>/dev/null || failed "busy session was killed"
[ "$(tmux list-panes -t =busy: -F '#{pane_current_command}' 2>/dev/null | sort | tr '\n' ' ')" \
  = "bash bash cat " ] || failed "busy should keep its cat and script panes"
[ "$(pgrep -fx "bash -c $job" | wc -l)" -eq 2 ] || failed "a script was stopped"
tmux capture-pane -p -t "$cat_pane" 2>/dev/null | grep -q exit \
  && failed "\"exit\" was typed into the cat pane"
[ $fail = 0 ] || tr -d '\r' <"$LOG"

tmux kill-server 2>/dev/null
# shellcheck disable=SC2046 # one PID per word
kill $(jobs -p) 2>/dev/null
rm -rf "$TMUX_TMPDIR" "$SANDBOX"
[ $fail = 0 ] && echo OK
exit $fail
