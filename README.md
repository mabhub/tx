# tx

An interactive tmux session manager that also keeps you from forgetting
sessions you left running.

- **`tx`** lists every tmux session: windows, creation and last-activity
  times, and for attached sessions *where each client connects from*
  (local terminal, ssh with the remote address, mosh, nested tmux). Pick a
  session to attach, rename or close it, or create a new one. A live preview
  of the session's content is shown as you move through the list.
- **`tx here`** opens the session of the current directory, and creates it
  there, with a command of your choice in its first pane, if it does not
  exist yet.
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

| Command                         | Effect                                                         |
|---------------------------------|----------------------------------------------------------------|
| `tx`                            | Interactive menu                                               |
| `tx here [-n NAME] [COMMAND…]`  | Session of the current directory: attach, or create it         |
| `tx init zsh\|bash`             | Print the shell integration code to `eval`                     |
| `tx notice`                     | Print the one-line notice (what the shell runs at startup)     |
| `tx notice --exit`              | Blocking reminder (what the shell runs on exit)                |
| `tx --help`                     | Short help                                                     |

In the menu, Enter selects and Escape goes back (or quits from the session
list). For a selected session:

- **Attach**: if other clients are already attached, choose between
  detaching them or sharing the session.
- **Rename**: the field starts with the current name, to edit rather than
  retype. Names with `.` or `:` are refused, since tmux would not keep them
  as typed (tmux 3.4 turns them into `_`).
- **Close**: sends Ctrl-C then `exit` to the panes whose shell waits at its
  prompt, so they shut down cleanly. Busy panes are listed before you
  confirm and left untouched: a program (an editor, a REPL, a long job), a
  running script, or a shell holding a job suspended with Ctrl-Z, shown as
  `(suspended job)`. Typing `exit` there would end up in the program's input,
  or take the suspended job down. Once the shells have exited, `tx` lists the
  panes left, if any, and offers `kill-session`; with no idle shell at all,
  that is the only question.

From inside tmux, attaching to a session or creating one switches the
current client to it, since tmux refuses to attach from within a session.

### One session per project: `tx here`

`tx here` opens the session of the current directory, named after it or
after `-n NAME` (`.` and `:` become `_` in both cases). If the session exists,
`tx` attaches to it; otherwise it creates it in this directory. A command
given after `here` is typed into the first pane of a new session, as if you
had typed it at the prompt: shell functions and aliases work, and the pane
goes back to its shell when the command exits. An existing session is
attached as is, without running the command again.

As with `ssh`, the arguments are joined with spaces and typed as is, so the
shell of the pane interprets them: `tx here 'make && vim .'` runs both
commands, and an argument that must keep its spaces needs a second level of
quotes (`tx here vim "'my notes.md'"`).

```sh
cd ~/projects/api
tx here             # session "api"
tx here -n api-v2   # same directory, another session name
tx here vim .       # new session: vim in the first pane
```

To open a project with your editor or assistant in one word, an alias is
enough: `alias work='tx here vim .'`.

If a session with that name exists but was started in another directory,
`tx here` stops and asks for another name (`-n`), rather than mixing two
projects that share a directory name. Attaching works as in the menu: the
detach or share choice, and the switch from inside tmux.

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
tests/rename.sh
tests/init.sh
tests/here.sh
```

They start an isolated tmux server, without your `~/.tmux.conf` (your
sessions are left alone).
`tests/notice.sh` attaches simulated local and ssh clients, and checks the
notice. `tests/close.sh` closes sessions from the numbered menu and checks
that a pane running a program is left untouched. `tests/rename.sh` checks
that renaming starts from the current name. `tests/init.sh` checks the
code printed by `tx init`: in bash, an earlier `EXIT` trap still runs, and
evaluating the code twice installs the exit hook once. `tests/here.sh`
checks `tx here`: a new session with its command, attaching again (share,
then detach), the refusal of a same-named session started elsewhere, the
same directory reached through a symlink, `-n`, `--help`, and the switch from
inside tmux, also to a session created from the menu.

On a Mac, `tests/macos-report.sh` also checks the bash version guard,
`tx init` and the numbered menu, then writes `tx-macos-report.txt`, worth
attaching to a bug report.

CI runs `shellcheck`, then the tests on Linux, and
`tests/macos-report.sh` (which runs them) on macOS.

## License

[MIT](LICENSE)
