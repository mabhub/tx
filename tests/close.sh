#!/usr/bin/env bash
# Checks that closing a session from the menu only types into idle shells:
# a pane running another program, a script (which tmux names "bash" like a
# shell) or a shell holding a suspended job must survive, without "exit" in
# its input.
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

fail=0
failed() { printf 'FAIL: %s\n' "$1"; fail=1; }

shell=(bash --norc --noprofile)
job='sleep 600; : tx-test-job'  # a script, which tmux shows as "bash"
tmux new-session -d -s idle "${shell[@]}"
tmux new-session -d -s busy -x 120 -y 60 "${shell[@]}"  # room for 5 panes
tmux new-session -d -s stuck cat  # no shell at all: kill-session is offered at once
# "exit" typed into cat would show up in the pane.
cat_pane=$(tmux split-window -d -P -F '#{pane_id}' -t =busy: cat)
tmux split-window -d -t =busy: bash -c "$job"  # the pane's own command
job_pane=$(tmux split-window -d -P -F '#{pane_id}' -t =busy: "${shell[@]}")
tmux send-keys -t "$job_pane" "bash -c '$job'" Enter  # started from a prompt
stop_pane=$(tmux split-window -d -P -F '#{pane_id}' -t =busy: "${shell[@]}")
tmux send-keys -t "$stop_pane" "bash -c '$job'" Enter
stop_shell=$(tmux display-message -p -t "$stop_pane" '#{pane_pid}')
stopped() { ps -o stat= -p "$(pgrep -P "$stop_shell")" 2>/dev/null | grep -q '^T'; }
for _ in $(seq 20); do pgrep -P "$stop_shell" >/dev/null && break; sleep 0.25; done
tmux send-keys -t "$stop_pane" C-z  # suspended, like an editor after Ctrl-Z
for _ in $(seq 20); do stopped && break; sleep 0.25; done
# Otherwise the pane would look busy for another reason, and prove nothing.
stopped || failed "the job in $stop_pane did not get suspended"

# The list reads "1) + new session  2) busy  3) idle  4) stuck", the session
# menu "1) Attach  2) Rename  3) Close". Close idle, then busy (declining the
# kill-session offered for the panes left), then stuck (where kill-session
# is the only question, declined too), and quit.
input=$'3\n3\ny\n2\n3\ny\nn\n3\n3\nn\nq\n'
# exec: the job's PID becomes this sleep, so the final kill stops it too.
{ sleep 2; printf '%s' "$input"; exec sleep 30; } | PATH=$SANDBOX pty "$TX" >"$LOG" 2>&1 &
pid=$!
for _ in $(seq 40); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done

kill -0 "$pid" 2>/dev/null && failed "tx did not quit"
tmux has-session -t =idle 2>/dev/null && failed "idle session still open"
tmux has-session -t =busy 2>/dev/null || failed "busy session was killed"
tmux has-session -t =stuck 2>/dev/null || failed "stuck session was killed"
grep -q 'suspended job' "$LOG" || failed "the suspended job was not pointed out"
grep -q 'No pane is waiting at a shell prompt' "$LOG" \
  || failed "kill-session was not offered at once for stuck"
[ "$(tmux list-panes -t =busy: -F '#{pane_current_command}' 2>/dev/null | sort | tr '\n' ' ')" \
  = "bash bash bash cat " ] || failed "busy should keep its cat and script panes"
[ "$(pgrep -fx "bash -c $job" | wc -l)" -eq 3 ] || failed "a script was killed"
for p in "$cat_pane" "$stop_pane"; do
  tmux capture-pane -p -t "$p" 2>/dev/null | grep -q exit \
    && failed "\"exit\" was typed into pane $p"
done
[ $fail = 0 ] || tr -d '\r' <"$LOG"

tmux kill-server 2>/dev/null
# shellcheck disable=SC2046 # one PID per word
kill $(jobs -p) 2>/dev/null
rm -rf "$TMUX_TMPDIR" "$SANDBOX"
[ $fail = 0 ] && echo OK
exit $fail
