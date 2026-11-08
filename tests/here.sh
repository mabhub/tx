#!/usr/bin/env bash
# Checks `tx here` on an isolated tmux server (never touches your real
# sessions): creation in the current directory with COMMAND typed in the
# first pane as is, attaching again from the same directory reached through
# another path (share, then detach the other clients), refusal of a
# same-named session started elsewhere, -n, --help, and, from inside tmux,
# switching the client, staying put when already there, and switching to a
# session created from the menu.
# script(1) gives each client a pty; fzf is hidden outside tmux.
# Usage: tests/here.sh [path/to/tx]
set -u
TX=${1:-$(cd "$(dirname "$0")/.." && pwd)/tx}
export LC_ALL=C
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
start_test_server
LOG=$TMUX_TMPDIR/here.log
SANDBOX=$(mktemp -d /tmp/txb.XXXX) || exit 1
mkdir -p "$SANDBOX/bin" "$SANDBOX/my.proj" "$SANDBOX/other/my.proj" "$SANDBOX/next"
ln -s "$SANDBOX" "$SANDBOX/link"
# A PATH without fzf: tx falls back to its numbered menu, which reads stdin.
no_fzf_path "$SANDBOX/bin"

fail=0
failed() { printf 'FAIL: %s\n' "$1"; fail=1; }
wait_for() { # wait_for CMD ARGS...: true once CMD succeeds, false after 10 s
  local _
  for _ in $(seq 50); do "$@" && return 0; sleep 0.2; done
  return 1
}
clients() { tmux list-clients -t "=$1" -F x 2>/dev/null | wc -l | tr -d ' '; }
has_clients() { [ "$(clients "$1")" = "$2" ]; }  # has_clients SESSION COUNT
pane() { tmux capture-pane -p -t "=$1:" 2>/dev/null; }
# shellcheck disable=SC2329 # called through wait_for
pane_has() { pane "$1" | grep -q "$2"; }  # pane_has SESSION REGEX
same_dir() { # same_dir SESSION DIR: the session was started in DIR, symlinks resolved
  local p
  p=$(tmux display-message -p -t "=$1:" '#{session_path}' 2>/dev/null)
  [ "$(cd "$p" && pwd -P)" = "$(cd "$2" && pwd -P)" ]
}
here() { # here INPUT ARGS...: tx here ARGS in a pty, INPUT typed after 2 s, kept attached
  local input=$1; shift
  { sleep 2; printf '%s' "$input"; exec sleep 600; } \
    | PATH=$SANDBOX/bin pty "$TX" here "$@" >>"$LOG" 2>&1 &
}

# The server runs before tx starts it (no ~/.tmux.conf), with bare shells.
tmux new-session -d -s keep bash --norc --noprofile
tmux set-option -g default-command 'bash --norc --noprofile'

# 1. New session, named after the directory ("." becomes "_"), COMMAND typed
#    as is in its first pane: the pane's shell reads the quotes and the &&.
#    Started through a symlink, which tmux keeps in the session's path.
cd "$SANDBOX/link/my.proj" || exit 1
here "" 'echo "hello  world" &&' echo finished
wait_for has_clients my_proj 1 || failed "tx here did not create and attach my_proj"
same_dir my_proj "$SANDBOX/my.proj" || failed "my_proj was not started in its directory"
wait_for pane_has my_proj '^finished$' || failed "COMMAND did not run in the first pane"
pane_has my_proj '^hello  world$' || failed "COMMAND was not typed as is"

# 2. Existing session already attached, reached through its physical path:
#    "2" shares it, COMMAND is not typed again.
cd "$SANDBOX/my.proj" || exit 1
here $'2\n' echo again
wait_for has_clients my_proj 2 || failed "sharing my_proj did not add a client"
grep -q 'already attached' "$LOG" || failed "no detach/share choice for an attached session"
pane my_proj | grep -q again && failed "COMMAND was typed into an existing session"

# 3. "1" detaches the two other clients.
here $'1\n'
wait_for has_clients my_proj 1 || failed "detaching the other clients of my_proj failed"

# 4. Same directory name elsewhere: refused, the session is left alone.
cd "$SANDBOX/other/my.proj" || exit 1
out=$("$TX" here 2>&1) && failed "a same-named session started elsewhere was accepted"
case $out in *"already exists, started in"*) ;; *) failed "unclear refusal: $out" ;; esac

# 5. -n picks another name.
here "" -n other
wait_for has_clients other 1 || failed "tx here -n other did not create and attach other"
same_dir other "$SANDBOX/other/my.proj" || failed "other was not started in its directory"

# --help: usage on stdout, success.
out=$("$TX" here --help 2>/dev/null) || failed "tx here --help failed"
case $out in "Usage: tx here"*) ;; *) failed "tx here --help printed: $out" ;; esac

# 6. From inside tmux (the pane of the client attached to other): the client
#    switches to the new session instead of nesting an attach.
tmux send-keys -t '=other:' -l "cd $(printf %q "$SANDBOX/next") && $(printf %q "$TX") here"
tmux send-keys -t '=other:' Enter
# shellcheck disable=SC2329 # called through wait_for
switched() { has_clients next 1 && has_clients other 0; }
wait_for switched || failed "tx here inside tmux did not switch the client to next"

# 7. Already in that session: tx says so and stays.
tmux send-keys -t '=next:' -l "$(printf %q "$TX") here"
tmux send-keys -t '=next:' Enter
wait_for pane_has next 'already in session "next"' || failed "no message when already in the session"
has_clients next 1 || failed "the client left next"

# 8. Menu inside tmux, numbered (no fzf): "+ new session" named "made", then
#    the client switches to it.
tmux send-keys -t '=next:' -l "PATH=$(printf %q "$SANDBOX/bin") $(printf %q "$TX")"
tmux send-keys -t '=next:' Enter
wait_for pane_has next 'new session' || failed "no menu inside tmux"
tmux send-keys -t '=next:' -l 1
tmux send-keys -t '=next:' Enter
wait_for pane_has next 'New session name' || failed "no name prompt for a new session"
tmux send-keys -t '=next:' -l made
tmux send-keys -t '=next:' Enter
# shellcheck disable=SC2329 # called through wait_for
switched_made() { has_clients made 1 && has_clients next 0; }
wait_for switched_made || failed "a session created from the menu inside tmux was not switched to"

[ $fail = 0 ] || { tr -d '\r' <"$LOG"; pane next; pane made; }
[ $fail = 0 ] && echo OK
exit $fail
