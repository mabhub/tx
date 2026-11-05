# tx

An interactive tmux session manager that also keeps you from forgetting
sessions you left running.

- **`tx`** lists every tmux session: windows, creation and last-activity
  times, and for attached sessions *where each client connects from*
  (local terminal, ssh with the remote address, mosh, nested tmux). Pick a
  session to attach, rename or close it, or create a new one. A live preview
  of the session's content is shown as you move through the list.
- **Shell integration** prints a one-line notice when a terminal opens, and
  a blocking reminder when you close the last local terminal, if there are
  sessions you could lose track of: detached sessions, and sessions attached
  from another machine over ssh or mosh.

```
tmux: 1 detached session (build) and 1 session attached remotely (notes) → tx
```

The interface is in English or French, following the locale (`LC_ALL`,
`LC_MESSAGES`, then `LANG`): French when it starts with `fr`, English
otherwise. Run `LC_ALL=C tx` to force English.

## Requirements

- Linux or macOS
- bash ≥ 4.4 (`tx` stops with a clear message on older versions). macOS ships
  bash 3.2: install a recent one with `brew install bash`
- tmux
- [fzf](https://github.com/junegunn/fzf), optional: without it `tx` falls back
  to a numbered menu

On macOS: `brew install bash tmux fzf` (conda-forge also has all three, for
instance through micromamba). Tested by hand on macOS 13 (Intel) in
Terminal.app, and in CI on the latest macOS. iTerm2 has not been tried.

## Installation

```sh
git clone https://github.com/mabhub/tx.git ~/projets/tx
ln -s ~/projets/tx/tx ~/bin/tx        # any directory on your PATH
```

Then enable the notices in your shell startup file:

```sh
# ~/.zshrc
command -v tx >/dev/null && eval "$(tx init zsh)"

# ~/.bashrc
command -v tx >/dev/null && eval "$(tx init bash)"
```

The generated code only runs in interactive shells outside tmux, and does
nothing if tmux is not installed. In bash, an `EXIT` trap set earlier in
`.bashrc` is kept and still runs.

### Suggested: session name as the terminal title

By default the terminal window or tab shows the name of the last command
run, such as `tx` or `tmux`. To show the tmux session name instead, add to
`~/.tmux.conf`:

```tmux
set -g set-titles on
set -g set-titles-string "#S"
```

tmux then updates the title on attach, on session switch and on rename
(including from `tx`). `"#S · #W"` adds the active window name. Reload with
`tmux source-file ~/.tmux.conf`.

## Usage

| Command             | Effect                                                  |
|---------------------|---------------------------------------------------------|
| `tx`                | Interactive menu                                        |
| `tx init zsh\|bash` | Print the shell integration code to `eval`              |
| `tx notice`         | Print the one-line notice (what the shell runs at startup) |
| `tx notice --exit`  | Blocking reminder (what the shell runs on exit)         |
| `tx --help`         | Short help                                              |

In the menu, Enter selects and Escape goes back (or quits from the session
list). For a selected session:

- **Attach**: if other clients are already attached, choose between
  detaching them or sharing the session.
- **Rename**: names with `.` or `:` are refused, since tmux would not keep
  them as typed (tmux 3.4 turns them into `_`).
- **Close**: sends Ctrl-C then `exit` to the panes sitting at a shell prompt,
  so they shut down cleanly. Panes running another program (an editor, a
  REPL, a long job) are listed before you confirm and left untouched: typing
  `exit` there would end up in the program's input. After up to 5 seconds,
  if panes remain, `tx` lists them and offers `kill-session`.

Attaching or creating an attached session is not possible from inside tmux;
`tx` tells you to detach first.

## How it works

### Where a client connects from

For each tmux client, `tx` reads its process:

1. If its environment contains `SSH_CONNECTION`, the client came in over ssh
   and the remote address is shown.
2. Otherwise it walks up the parent processes, skipping shells, `sudo`,
   `su`, `login` and the like, until it finds what started the chain: an
   `sshd` or `mosh` process (remote), the tmux server (nested tmux), or any
   other program, usually the terminal emulator (local).

### The exit reminder

When a shell exits, the reminder is shown only if the terminal is really
going away and nothing else would remind you of your sessions:

- Nested shells (a shell started from another shell) are ignored: the
  terminal stays open.
- If another *local* terminal is still open, nothing is shown. Terminals
  opened over ssh or mosh do not count. The goal is to warn you before you
  shut down the machine, and a remote connection does not prevent that.

The reminder lists the sessions that would be left behind. Press Enter to
close the terminal anyway, or `t` to open `tx` and deal with them first.

The reminder needs the shell to exit by itself (`exit`, Ctrl-D). In
Terminal.app, closing the window (⌘W or the close button) ends the shell at
once, and nothing is shown.

## Tests

```sh
tests/notice.sh
tests/close.sh
```

Both start an isolated tmux server (your sessions are left alone).
`tests/notice.sh` attaches simulated local and ssh clients, and checks the
notice. `tests/close.sh` closes sessions from the numbered menu and checks
that a pane running a program is left untouched.

On a Mac, `tests/macos-report.sh` also checks the bash version guard,
`tx init` and the numbered menu, then writes `tx-macos-report.txt`, worth
attaching to a bug report.

CI runs `shellcheck`, then `tests/notice.sh` and `tests/close.sh` on Linux,
and `tests/macos-report.sh` (which runs both) on macOS.

## License

[MIT](LICENSE)
