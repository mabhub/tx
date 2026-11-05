# Helpers shared by the tests, which source this file. Written for the
# bash 3.2 of macOS, like tests/macos-report.sh.

# The tests' own tmux server ignores ~/.tmux.conf: plugins, hooks or options
# such as remain-on-exit would change the results.
tmux() { command tmux -f /dev/null "$@"; }

start_test_server() { # isolated tmux server, removed on exit with the test's jobs and $SANDBOX
  # Short socket path: Unix sockets are limited to about 100 characters.
  # Stop if it fails: with an empty TMUX_TMPDIR, tmux falls back to the real
  # server, which cleanup would kill.
  TMUX_TMPDIR=$(mktemp -d /tmp/txt.XXXX) || exit 1
  export TMUX_TMPDIR
  trap cleanup EXIT
  unset TMUX
  # tmux clients need a usable TERM (CI has none, or "dumb").
  case ${TERM:-dumb} in dumb) export TERM=xterm ;; esac
}

cleanup() {  # also when interrupted: test panes may run sleep 600
  tmux kill-server 2>/dev/null
  # shellcheck disable=SC2046 # one PID per word
  kill $(jobs -p) 2>/dev/null
  rm -rf "$TMUX_TMPDIR" "${SANDBOX:-}"
}

pty() { # pty CMD...: runs CMD in a new pty (Linux and BSD script syntaxes)
  case $(uname -s) in
    Linux) script -qfc "$(printf '%q ' "$@")" /dev/null ;;
    *)     script -q /dev/null "$@" ;;
  esac
}

no_fzf_path() { # no_fzf_path DIR: fills DIR with /bin and /usr/bin minus fzf, to use as PATH
  local t
  for t in bash tmux; do ln -s "$(type -P "$t")" "$1/$t"; done
  # Names already linked are kept: ln reports them and goes on.
  ln -s /bin/* "$1/" 2>/dev/null; ln -s /usr/bin/* "$1/" 2>/dev/null
  rm -f "$1/fzf"
}
