# ai-revive

Your tmux/byobu workspace survives a reboot: every session, window, pane, working directory and
layout comes back, and so does the program that was running in each pane. Claude Code
conversations are resumed by session id (two Claude panes in one directory stay two different
conversations), ssh connections are re-established with their original command line, and any
other program can be whitelisted. Works as a plain tmux plugin (TPM compatible) and integrates
with byobu on Ubuntu. GPL-3.0-or-later.

| What | Where |
|---|---|
| `bin/ai-revive` | the CLI: `save`, `restore`, `list`, `status`, `enable`, `disable`, `resumers`, `shutdown`, `reboot` |
| `bin/byobu-ai-revive` | same CLI, byobu flavour (acts on the byobu config dir) |
| `ai-revive.tmux` | plugin entry point run at tmux server start: installs hooks + key bindings, starts the auto-restore |
| `lib/` | bash libraries (save, restore, resumer dispatch, enable, config, snapshot files) |
| `resumers/` | `10-claude`, `20-ssh`, `90-whitelist` — see `man ai-revive-resumers` for writing your own |
| `systemd/user/` | periodic save timer and best-effort shutdown save |
| `examples/config` | every setting with its default |
| `man/` | `ai-revive(1)`, `ai-revive-resumers(7)` |
| `tests/` | `run-tests.sh` runs `test-*.sh`, each on a private tmux server with fake `claude`/`ssh` |
| `debian/` | packaging; `make deb-docker` builds the `.deb` in a clean `ubuntu:24.04` |

## Install

From a release: `sudo apt install ./ai-revive_<version>_all.deb`, then as your user:

```
ai-revive enable      # wires the plugin into byobu (or ~/.tmux.conf), hooks, systemd timer
ai-revive status
```

From a checkout, without installing anything: `bin/ai-revive enable` does the same and points the
configuration at the checkout. With TPM instead: `set -g @plugin 'bumml/ai-revive'` in `~/.tmux.conf`.

## Daily use

```
ai-revive save                 # snapshot now (hooks and the timer do this for you)
ai-revive restore --dry-run    # what a restore would do
ai-revive restore              # rebuild missing windows and relaunch their programs
ai-revive list                 # snapshots on disk
ai-revive resumers probe %3    # which resumer claims pane %3 and what it would run
ai-revive reboot               # save, then reboot — the reliable way to power off
```

Inside tmux: `prefix + C-s` saves, `prefix + C-r` restores (byobu's prefix is F12 or ctrl-a).

## How a reboot works

1. Hooks save on every new window, split, rename or layout change (debounced), the systemd user
   timer every 5 minutes, and `ai-revive reboot` right before going down.
2. After logging in, `byobu` starts a fresh tmux server. Its configuration runs `ai-revive.tmux`,
   which starts `ai-revive restore --auto` in the background.
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
make deb-docker    # dist/ai-revive_<version>_all.deb built and lintian-checked in ubuntu:24.04
make install PREFIX=~/.local   # or DESTDIR=... PREFIX=/usr for packaging
```

## Adding a resumer

1. Copy `resumers/20-ssh` to `~/.config/ai-revive/resumers/NN-name` (or into `resumers/` for a
   shipped one). `NN` fixes the order; the first resumer that claims a pane wins.
2. Implement `probe`: inspect `$AI_REVIVE_PANE_PID`'s children, exit 1 to pass, or print
   `{"cmd": "...", "cwd": "...", "meta": {}}` and exit 0. `cmd` is typed into a shell, so quote
   it with `shell_quote` / `proc_cmdline_to_shell` from `lib/common.sh`.
3. `ai-revive resumers probe %<pane>` on a live pane, then add a `tests/test-resumer-name.sh`
   with a fake program under `tests/fakes/` (see `test-resumer-ssh.sh`).

## Changing the snapshot format

`lib/save.sh` builds the document (`version: 1`), `lib/restore.sh` consumes it. Bump `version`
for incompatible changes and keep `restore` reading the old one; `tests/test-restore.sh` and
`tests/test-resumer-claude.sh` are the round-trip tests.

## Other machines

Install the release `.deb` and run `ai-revive enable` as each user.

## Release

Tag `v<version>` matching `VERSION` and `debian/changelog`; CI runs lint + tests, builds the
`.deb` in `ubuntu:24.04`, runs lintian and attaches it to the Gitea release.
