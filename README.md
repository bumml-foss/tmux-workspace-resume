# tmux-workspace-resume

Your tmux or byobu workspace survives a reboot. Sessions, windows, panes, layouts and working
directories come back, and so does the program in each pane: Claude Code, OpenAI Codex CLI,
Gemini CLI and GitHub Copilot CLI resume their exact conversation by session id, ssh reconnects,
and other programs can be whitelisted. GPL-3.0-or-later.

## Install

Debian or Ubuntu, with the `.deb` from the project's releases page:

```sh
sudo apt install ./tmux-workspace-resume_0.2.0_all.deb
tmux-workspace-resume enable
```

From source (needs `tmux` 3.0+, `jq`, `make`):

```sh
git clone https://github.com/bumml-foss/tmux-workspace-resume
cd tmux-workspace-resume
make install PREFIX=~/.local
tmux-workspace-resume enable
```

With [TPM](https://github.com/tmux-plugins/tpm), add this to `~/.tmux.conf` and press `prefix + I`:

```tmux
set -g @plugin 'bumml-foss/tmux-workspace-resume'
```

`enable` wires the plugin into byobu (or `~/.tmux.conf` for plain tmux) and starts a systemd user
timer that saves every 5 minutes. A TPM install saves on every layout change and on demand, but
has no timer.

## Use

Nothing to do: the workspace is saved whenever it changes, and restored when tmux starts after a
reboot. By hand, inside tmux: `prefix + Ctrl-s` saves, `prefix + Ctrl-r` restores (byobu's prefix
is F12 or Ctrl-a).

```sh
tmux-workspace-resume status               # is everything wired up?
tmux-workspace-resume restore --dry-run    # what a restore would do
tmux-workspace-resume reboot               # save, then reboot: the most exact snapshot
```

## Coming from tmux-resurrect

[tmux-resurrect](https://github.com/tmux-plugins/tmux-resurrect), usually paired with
[tmux-continuum](https://github.com/tmux-plugins/tmux-continuum) for automatic saves, is the
long-standing plugin for this, and works on macOS and old tmux versions, which this one does not.
What tmux-workspace-resume adds:

- agents resume their own conversation by session id, instead of starting a new one
- saves on every window, split, rename and layout change, and on a timer that runs while detached
- a snapshot from before a reboot is never overwritten before it was restored
- layouts are scaled to the terminal they are restored into
- pipelines, `sudo <program>` and serial consoles (by their `/dev/serial/by-id` name) come back

Your last tmux-resurrect save, with its pane contents, can be brought over:

```sh
tmux-workspace-resume import               # reads ~/.local/share/tmux/resurrect/last (or ~/.tmux/...)
tmux-workspace-resume restore <snapshot>   # the command `import` printed
```

Then remove tmux-resurrect and tmux-continuum from `~/.tmux.conf`: both plugins bind
`prefix + Ctrl-s` / `Ctrl-r`, and continuum would keep saving and restoring on its own.

## Limitations

- Programs are started again, not continued: a running agent's current turn is lost, and so is
  the scrollback unless `SCROLLBACK_LINES` is set.
- The Codex, Gemini and Copilot resumers are tested against fake programs only.
- The save at shutdown is best effort; the last snapshot is at most 5 minutes old.

## Uninstall

```sh
tmux-workspace-resume disable
sudo apt remove tmux-workspace-resume      # or: make uninstall PREFIX=~/.local
```

## More

`man tmux-workspace-resume` for every command and setting, `man tmux-workspace-resume-resumers`
for writing your own resumer, [CONTRIBUTING.md](CONTRIBUTING.md) for development.
