# tmux-workspace-resume

Your tmux/byobu workspace survives a reboot: every session, window, pane, working directory and
layout comes back, and so does the program that was running in each pane. AI coding agents are
resumed by session id: Claude Code, OpenAI Codex CLI, Gemini CLI and GitHub Copilot CLI (two
agent panes in one directory stay two different conversations). ssh connections are
re-established with their original command line, and any other program can be whitelisted. Works as a plain tmux plugin (TPM compatible) and integrates
with byobu on Ubuntu. GPL-3.0-or-later.

| What | Where |
|---|---|
| `bin/tmux-workspace-resume` | the CLI: `save`, `restore`, `list`, `status`, `enable`, `disable`, `resumers`, `shutdown`, `reboot` |
| `bin/byobu-tmux-workspace-resume` | same CLI, byobu flavour (acts on the byobu config dir) |
| `tmux-workspace-resume.tmux` | plugin entry point run at tmux server start: installs hooks + key bindings, starts the auto-restore |
| `lib/` | bash libraries (save, restore, resumer dispatch, enable, config, snapshot files, layout scaling, agent helpers) |
| `resumers/` | `10-claude`, `20-ssh`, `30-codex`, `40-gemini`, `50-copilot`, `90-whitelist` — see `man tmux-workspace-resume-resumers` for writing your own |
| `systemd/user/` | periodic save timer and best-effort shutdown save |
| `examples/config` | every setting with its default |
| `man/` | `tmux-workspace-resume(1)`, `tmux-workspace-resume-resumers(7)` |
| `tests/` | `run-tests.sh` runs `test-*.sh`, each on a private tmux server with fake `claude`/`codex`/`gemini`/`copilot`/`ssh` executables that write the real tools' session files |
| `debian/` | packaging; `make deb-docker` builds the `.deb` in a clean `ubuntu:24.04` |

## Install

From a release: `sudo apt install ./tmux-workspace-resume_<version>_all.deb`, then as your user:

```
tmux-workspace-resume enable      # wires the plugin into byobu (or ~/.tmux.conf), hooks, systemd timer
tmux-workspace-resume status
```

From a checkout, without installing anything: `bin/tmux-workspace-resume enable` does the same and points the
configuration at the checkout. With TPM instead: `set -g @plugin 'bumml-foss/tmux-workspace-resume'` in `~/.tmux.conf`.

## Daily use

```
tmux-workspace-resume save                 # snapshot now (hooks and the timer do this for you)
tmux-workspace-resume restore --dry-run    # what a restore would do
tmux-workspace-resume restore              # rebuild missing windows and relaunch their programs
tmux-workspace-resume list                 # snapshots on disk
tmux-workspace-resume resumers probe %3    # which resumer claims pane %3 and what it would run
tmux-workspace-resume reboot               # save, then reboot — the reliable way to power off
```

Inside tmux: `prefix + C-s` saves, `prefix + C-r` restores (byobu's prefix is F12 or ctrl-a).

## How a reboot works

1. Hooks save on every new window, split, rename or layout change (debounced), the systemd user
   timer every 5 minutes, and `tmux-workspace-resume reboot` right before going down.
2. After logging in, `byobu` starts a fresh tmux server. Its configuration runs `tmux-workspace-resume.tmux`,
   which starts `tmux-workspace-resume restore --auto` in the background.
3. The snapshot is from a previous boot, so the placeholder session is renamed and filled with the
   saved windows, names, layouts and directories. Once each pane's shell shows a prompt, its
   program is typed in: `cd <dir> && claude --resume <id>`, `ssh -p 2222 host`, ...
4. Windows that already exist are never touched, so a second `byobu`, a manual `restore` or a
   `prefix + C-r` are all harmless.

`AUTO_RESTORE=reboot` (default) restores only when the snapshot is from an earlier boot; a
deliberate `tmux kill-server` then starts clean. `always` restores whenever the server starts
fresh, `never` leaves it to `prefix + C-r`. Everything else: `examples/config`.

## Development

```
make lint          # shellcheck + bash -n
make test          # tests/run-tests.sh — private tmux servers only, never your own session
make audit         # privacy audit of the whole history; must pass before any public push
make deb-docker    # dist/tmux-workspace-resume_<version>_all.deb built and lintian-checked in ubuntu:24.04
make install PREFIX=~/.local   # or DESTDIR=... PREFIX=/usr for packaging
```

## How agents are matched to their sessions

Claude Code records the tmux pane it runs in, so its resumer is exact. Codex, Gemini and Copilot
do not, so their resumers find the agent's process under the pane's shell and identify the
session by, in order: a session file the process holds open; the session id on its command line
(`--resume <id>`, which is how a restore relaunches them); the session created soonest after the
process started in the process's directory (or, for a resumed session, the most recently
modified one); and as a last resort the command line the agent was started with. Two new agents
started in the same directory within the same second cannot be told apart. These three were
written from the tools' published formats and tested against fakes that reproduce those
formats, not against the real binaries; `tmux-workspace-resume resumers probe %<pane>` shows what a live
pane would get.

## Adding a resumer

1. Copy `resumers/20-ssh` to `~/.config/tmux-workspace-resume/resumers/NN-name` (or into `resumers/` for a
   shipped one). `NN` fixes the order; the first resumer that claims a pane wins.
2. Implement `probe`: inspect `$TWR_PANE_PID`'s children, exit 1 to pass, or print
   `{"cmd": "...", "cwd": "...", "meta": {}}` and exit 0. `cmd` is typed into a shell, so quote
   it with `shell_quote` / `proc_cmdline_to_shell` from `lib/common.sh`.
3. `tmux-workspace-resume resumers probe %<pane>` on a live pane, then add a `tests/test-resumer-name.sh`
   with a fake program under `tests/fakes/` (see `test-resumer-ssh.sh`).

## Changing the snapshot format

`lib/save.sh` builds the document (`version: 1`), `lib/restore.sh` consumes it. Bump `version`
for incompatible changes and keep `restore` reading the old one; `tests/test-restore.sh` and
`tests/test-resumer-claude.sh` are the round-trip tests.

## Other machines

Install the release `.deb` and run `tmux-workspace-resume enable` as each user.

## Release

Tag `v<version>` matching `VERSION` and `debian/changelog`; CI runs lint, the privacy audit and
the tests, builds the `.deb` in `ubuntu:24.04`, runs lintian and attaches it to the release for
the tag. Commits carry `Assisted-by:` for AI help and `Signed-off-by:` (`git commit -s`).
