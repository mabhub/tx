# Helpers shared by the tests, which source this file. Written for the
# bash 3.2 of macOS, like tests/macos-report.sh.

pty() { # pty CMD...: runs CMD in a new pty (Linux and BSD script syntaxes)
  case $(uname -s) in
    Linux) script -qfc "$(printf '%q ' "$@")" /dev/null ;;
    *)     script -q /dev/null "$@" ;;
  esac
}

no_fzf_path() { # no_fzf_path DIR: fills DIR with /bin and /usr/bin minus fzf, to use as PATH
  local t
  for t in bash tmux; do ln -s "$(command -v "$t")" "$1/$t"; done
  # Names already linked are kept: ln reports them and goes on.
  ln -s /bin/* "$1/" 2>/dev/null; ln -s /usr/bin/* "$1/" 2>/dev/null
  rm -f "$1/fzf"
}
