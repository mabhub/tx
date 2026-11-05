#!/usr/bin/env bash
# Checks `tx notice` and client-origin detection on an isolated tmux server
# (never touches your real sessions). ssh clients are simulated with
# SSH_CONNECTION; script(1) gives each fake client a pty.
# Usage: tests/notice.sh [path/to/tx]
set -u
TX=${1:-$(cd "$(dirname "$0")/.." && pwd)/tx}
export LC_ALL=C
# shellcheck source=tests/lib.sh
. "$(dirname "$0")/lib.sh"
start_test_server

client() { # client SESSION: attach a client inside a pty, kept open by a never-ending stdin
  sleep 600 | pty tmux attach -t "$1" >/dev/null 2>&1 &
}

for s in build notes mixte locale; do tmux new-session -d -s $s; done
SSH_CONNECTION="10.0.0.9 5555 10.0.0.1 22" client notes
SSH_CONNECTION="10.0.0.8 5556 10.0.0.1 22" client mixte
client mixte
client locale
for _ in $(seq 50); do [ "$(tmux list-clients 2>/dev/null | wc -l)" -ge 4 ] && break; sleep 0.2; done

out=$("$TX" notice 2>&1)

printf '%s\n' "$out"
fail=0
for want in "1 detached session (build)" "2 sessions attached remotely (" "notes" "mixte"; do
  case $out in *"$want"*) ;; *) printf 'FAIL: missing "%s"\n' "$want"; fail=1 ;; esac
done
case $out in *locale*) printf 'FAIL: "locale" is attached locally and must not be listed\n'; fail=1 ;; esac
[ $fail = 0 ] && echo OK
exit $fail
