# ai-revive

tmux/byobu workspace persistence across reboots, with pluggable resumers (Claude Code by session
id, ssh, whitelist). Usage, layout and workflows: `README.md`. Plain bash + jq, GPL-3.

## Hard rules

- **Never write `default-command` or `default-shell` into anything `enable` touches**, not even
  in a comment: `/usr/bin/byobu` greps the user's `.tmux.conf` for those strings and changes how
  it launches. `make lint` fails if `lib/enable.sh` contains them.
- **Never write a blank or empty snapshot over a richer one.** `save_now` keeps `last.json` when
  the server is the freshly started one-window placeholder, and never writes zero panes.
- **Tests never touch the developer's own tmux server, byobu config or systemd.** Every test
  sources `tests/lib/harness.sh`: private socket, temp HOME/XDG dirs, `AI_REVIVE_NO_SYSTEMD=1`.
- **Everything a resumer prints in `cmd` is typed into a shell.** Quote with `shell_quote` /
  `proc_cmdline_to_shell` (single-quote style, fish-safe), never `printf %q`.
- **Do not use `windows.tmux`** of byobu: when non-empty, byobu skips session selection on every
  launch. The hook point is the user's `.tmux.conf` (sourced last), via a marker block.
- tmux hooks live at index `[900]` so other plugins' hooks coexist. Use only hook names that exist
  in tmux 3.0+ (`tmux show-hooks -g` lists them; there is no `after-kill-window`).

## Conventions

- `#!/usr/bin/env bash`, `set -euo pipefail`, tabs. Shellcheck-clean with `.shellcheckrc`.
- tmux format output is parsed by having tmux emit tabs and `tr '\t' '\037'` before `IFS=$'\x1f' read`;
  tmux escapes control characters in formats and bash collapses consecutive tabs.
- Never pipe `ai-revive` or `tmux` output into `grep -q` in tests (SIGPIPE + pipefail); use the
  harness's `has PATTERN CMD...` or capture into a variable.
- `wait_until SECONDS 'condition'` takes a string evaluated each poll.
- The checkout, a TPM clone and `/usr/share/ai-revive` have the same layout
  (`ai-revive.tmux`, `lib/`, `resumers/`); `bin/ai-revive` finds `AI_REVIVE_HOME` from its own path.
- Match Claude panes on `@window.%pane` only; the session-name prefix in
  `~/.claude/sessions/<pid>.json` goes stale when byobu re-attaches.

## Verifying a change

```bash
make lint
make test                                  # all tests, private tmux servers
bin/ai-revive save && bin/ai-revive restore --dry-run     # against your live server: read-only
tmux -L scratch -f /dev/null new-session -d -x 200 -y 50; AI_REVIVE_TMUX_SOCKET_NAME=scratch bin/ai-revive restore --layout-only
make deb-docker                            # package + lintian
```

## Traps

- byobu attaches each client through a grouped clone session (`1`, `1-13`, ... in group `1`);
  save one session per `#{session_group}` and name it after the group.
- `tmux kill-server` followed immediately by `new-session` can hit the dying socket; the harness's
  `kill_server` waits.
- New panes are split from the newest pane so the pane list order equals the saved index order,
  which is what `select-layout` maps layout cells onto.
- `claude --resume <id>` refuses to run from a different directory; resumers pass `cwd`.
