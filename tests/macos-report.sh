#!/usr/bin/env bash
# Checks tx on a Mac and writes tx-macos-report.txt (in the repository root),
# to attach to a bug report. CI runs it on macOS. Takes about 45 seconds and
# needs no input.
# It installs nothing and changes no settings. It never touches your tmux
# sessions, because everything runs on a throwaway tmux server.
# Usage: tests/macos-report.sh
# Written for the bash 3.2 that ships with macOS, so it can still report a
# missing newer bash.
set -u
cd "$(dirname "$0")/.." || exit 1
REPO=$(pwd)
TX=$REPO/tx
REPORT=$REPO/tx-macos-report.txt

# Everything goes to the screen and to the report, with $HOME shown as ~.
exec 3>&1 > >(sed "s|$HOME|~|g" | tee "$REPORT") 2>&1
finish() { # finish STATUS: flush the report, then exit
  cleanup; trap - EXIT
  exec >&3 2>&3; sleep 1  # no writer left: sed and tee end
  printf '\nReport written to %s\n' "$REPORT"; exit "$1"
}

section() { printf '\n== %s\n' "$*"; }
note() { printf '%-28s %s\n' "$1" "$2"; }
RESULTS=""
result() { RESULTS+=$(printf '%-6s %s' "$1" "$2")$'\n'; }  # result PASS|FAIL|INFO TEXT

# shellcheck source=tests/lib.sh
. tests/lib.sh
start_test_server
kill_tree() { local c; for c in $(pgrep -P "$1"); do kill_tree "$c"; done; kill "$1" 2>/dev/null; }
in_pty() { # in_pty INPUT CMD...: types INPUT into CMD after 2 s, gives up after 15 s
  local input=$1 pid _; shift
  ( { sleep 2; printf '%s' "$input"; sleep 3; } | pty "$@" ) &
  pid=$!
  for _ in $(seq 30); do kill -0 "$pid" 2>/dev/null || break; sleep 0.5; done
  kill_tree "$pid"; wait "$pid" 2>/dev/null
}

if [ -n "${SSH_CONNECTION:-}" ]; then
  echo "WARNING: running over ssh. tx sees every client started from here as an"
  echo "ssh client, so the menu and notice checks fail. Run this script from a"
  echo "terminal window on the Mac itself."
fi

section "System"
command -v sw_vers >/dev/null && sw_vers
note "uname" "$(uname -srm)"
note "terminal" "${TERM_PROGRAM:-?} ${TERM_PROGRAM_VERSION:-}"
note "login shell" "${SHELL:-?}"
note "locale" "LANG=${LANG:-} LC_ALL=${LC_ALL:-} LC_MESSAGES=${LC_MESSAGES:-}"
note "date" "$(date '+%Y-%m-%d %H:%M %z')"
note "tx commit" "$(git -C "$REPO" log -1 --format='%h %s' 2>/dev/null || echo '?')"

section "Tools"
# shellcheck disable=SC2016 # expanded by the bash being tested
bash_version() { "$1" -c 'echo "${BASH_VERSINFO[0]}.${BASH_VERSINFO[1]}"' 2>/dev/null; }
note "bash on PATH" "$(command -v bash) $(bash_version bash)"
note "/bin/bash" "$(bash_version /bin/bash)"
BREW=$(command -v brew || true)
note "brew" "${BREW:-not found}"
NEWBASH=""
for b in "$(command -v bash)" ${BREW:+"$("$BREW" --prefix)/bin/bash"} /opt/homebrew/bin/bash /usr/local/bin/bash; do
  v=$(bash_version "$b") || continue
  case $v in 4.[4-9]*|[5-9].*) NEWBASH=$b; break ;; esac
done
note "bash used for tx" "${NEWBASH:-none found (brew install bash)}"
note "tmux" "$(tmux -V 2>/dev/null || echo 'not found (brew install tmux)')"
note "fzf" "$(fzf --version 2>/dev/null || echo 'not found (optional)')"
note "zsh" "$(zsh --version 2>/dev/null || echo 'not found')"

section "Version guard (tx run by /bin/bash)"
out=$(/bin/bash "$TX" --help 2>&1); printf '%s\n' "$out" | head -n 3
case $(bash_version /bin/bash) in
  [123].*|4.[0-3]) case $out in *"bash 4.4"*) result PASS "clear message on bash $(bash_version /bin/bash)" ;;
                                *) result FAIL "no clear message on bash $(bash_version /bin/bash)" ;; esac ;;
  *) result INFO "/bin/bash is recent: version guard not exercised" ;;
esac

if [ -z "$NEWBASH" ] || ! type -P tmux >/dev/null; then  # not the tmux function of lib.sh
  result FAIL "bash ≥ 4.4 or tmux missing: other checks skipped"
  section "Summary"; printf '%s' "$RESULTS"; finish 1
fi
PATH=$(dirname "$NEWBASH"):$PATH  # so that tx's "#!/usr/bin/env bash" finds it

section "tx --help and init"
"$TX" --help 2>&1 | head -n 2
LANG=fr_FR.UTF-8 LC_ALL='' LC_MESSAGES='' "$TX" --help 2>&1 | head -n 1
for sh in zsh bash; do
  command -v "$sh" >/dev/null || continue
  if "$TX" init "$sh" | "$sh" -n; then result PASS "tx init $sh: valid $sh code"
  else result FAIL "tx init $sh: syntax error"; fi
done

section "Process tree of this terminal (pid ppid name)"
p=$$
for _ in $(seq 12); do
  line=$(ps -o pid=,ppid=,comm= -p "$p" 2>/dev/null) || break
  read -r pid ppid comm <<<"$line"
  printf '%6s %6s %s\n' "$pid" "$ppid" "${comm##*/}"
  [ "${ppid:-0}" -le 1 ] && break
  p=$ppid
done

section "Terminal names (H4)"
mytty=$(ps -o tty= -p $$ | tr -d ' ')
note "this terminal" "$mytty"
note "all your terminals" "$(ps -u "$(id -u)" -o tty= | tr -d ' ' | sort -u | grep -v '^?*$' | tr '\n' ' ')"
case $mytty in ttys*|pts/*) result PASS "terminal name recognised ($mytty)" ;;
               '?'*|'') result INFO "no terminal (CI?): tests/notice.sh covers it" ;;
               *) result FAIL "terminal name not recognised by tx ($mytty)" ;; esac

section "tmux server process (H2)"
tmux new-session -d -s probe
ps -o comm=,command= -p "$(tmux list-sessions -F '#{pid}')"
tmux kill-server

section "Environment of another process through ps -E (H1)"
# Not with sleep: macOS hides the environment of its own programs, and tx only
# reads it from tmux clients, which never are.
SSH_CONNECTION="10.0.0.9 5555 10.0.0.1 22" "$NEWBASH" -c 'sleep 5; :' &
seen=$(ps -E -o command= -p $! 2>/dev/null | tr ' ' '\n' | grep '^SSH_CONNECTION=' || true)
if [ -r /proc/$$/environ ]; then result INFO "Linux: tx reads /proc, ps -E not used"
elif [ -n "$seen" ]; then result PASS "ps -E shows SSH_CONNECTION"
else result FAIL "ps -E does not show SSH_CONNECTION (ssh clients shown without address)"; fi
note "seen" "${seen:-nothing}"

section "Menu, numbered version (fzf hidden)"
# A PATH without fzf: tx falls back to its numbered menu, which can be driven from here.
SANDBOX=$(mktemp -d /tmp/txb.XXXX) || finish 1
no_fzf_path "$SANDBOX"
tmux new-session -d -s alone
tmux new-session -d -s here
sleep 600 | pty tmux attach -t here >/dev/null 2>&1 &
for _ in $(seq 25); do [ "$(tmux list-clients 2>/dev/null | wc -l)" -ge 1 ] && break; sleep 0.2; done
menu=$(PATH=$SANDBOX LANG=C LC_ALL='' in_pty $'q\n' "$TX" | tr -d '\r')
printf '%s\n' "$menu"
case $menu in *"here "*"attached"*"local"*) result PASS "menu lists sessions, local client recognised" ;;
              *"here "*) result FAIL "menu shown, but local client not recognised" ;;
              *) result FAIL "menu not shown" ;; esac
tmux kill-server 2>/dev/null

section "Notice test (tests/notice.sh)"
if tests/notice.sh "$TX"; then result PASS "tests/notice.sh"; else result FAIL "tests/notice.sh"; fi

section "Close test (tests/close.sh)"
if tests/close.sh "$TX"; then result PASS "tests/close.sh"; else result FAIL "tests/close.sh"; fi

section "Rename test (tests/rename.sh)"
if tests/rename.sh "$TX"; then result PASS "tests/rename.sh"; else result FAIL "tests/rename.sh"; fi

section "Init test (tests/init.sh)"
if tests/init.sh "$TX"; then result PASS "tests/init.sh"; else result FAIL "tests/init.sh"; fi

section "Summary"
printf '%s' "$RESULTS"
case $RESULTS in *FAIL*) finish 1 ;; *) finish 0 ;; esac
