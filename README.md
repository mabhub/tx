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
tmux : 1 session détachée (build) et 1 session attachée en ssh (notes) → tx
```

> The interface is currently in French.

## Requirements

- Linux (process origins are read from `/proc`)
- bash ≥ 4
- tmux
- [fzf](https://github.com/junegunn/fzf), optional: without it `tx` falls back
  to a numbered menu

## Installation

```sh
git clone <repository-url> ~/projets/tx
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
nothing if tmux is not installed.

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
- **Rename**: tmux forbids `.` and `:` in session names.
- **Close**: sends Ctrl-C then `exit` to every pane so programs can shut down
  cleanly, waits up to 5 seconds, and offers `kill-session` if some panes are
  still running.

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
