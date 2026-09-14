# ai-revive

tmux/byobu workspace persistence across reboots, with pluggable resumers (Claude Code by session
id, ssh, whitelist). Usage, layout and workflows: `README.md`. Plain bash + jq, GPL-3.

## Hard rules

- **Never write `default-command` or `default-shell` into anything `enable` touches**, not even
  in a comment: `/usr/bin/byobu` greps the user's `.tmux.conf` for those strings and changes how
  it launches. `make lint` fails if `lib/enable.sh` contains them.
- **Never overwrite a previous-boot snapshot before a restore had its chance.** `save_now` refuses
  while `last.json` carries another boot id and no completion marker (`restored-<boot>-<server pid>`)
  exists. The marker is written when a restore *completes*, or when `restore --auto` decides not
  to restore; a separate `attempted-` marker stops re-entry. `AUTO_RESTORE=never` and `--force`
  bypass the guard. Never write zero panes.
- **Tests never touch the developer's own tmux server, byobu config or systemd.** Every test
  sources `tests/lib/harness.sh`: private socket, temp HOME/XDG dirs, `AI_REVIVE_NO_SYSTEMD=1`.
- **Everything a resumer prints in `cmd` is typed into a shell.** Quote with `shell_quote` /
  `proc_cmdline_to_shell` (single-quote style, fish-safe), never `printf %q`.
- **Do not use `windows.tmux`** of byobu: when non-empty, byobu skips session selection on every
  launch. The hook point is the user's `.tmux.conf` (sourced last), via a marker block.
- tmux hooks live at index `[900]` so other plugins' hooks coexist. Use only hook names that exist
  in tmux 3.0+ (`tmux show-hooks -g` lists them; there is no `after-kill-window`).
- **Nothing private goes into the repository**, not in code, tests, docs or commit messages: no
  real session ids, host names, IP addresses or home paths from a developer machine, no e-mail
  addresses other than the project's. Examples use made-up values (`/home/me`,
  `12345678-90ab-...`). `make audit` scans the whole history (gitleaks, e-mail addresses, home
  paths, private hosts, real agent session ids on this machine, and a private denylist kept
  outside the repository); it must pass before anything is pushed to a public remote.

## Conventions

- Commits are signed off and credit AI help with a trailer, never a co-author line:
  `Assisted-by: Claude:<model id>` followed by `Signed-off-by: Benedikt Humml <bumml.foss@proton.me>`
  (`git commit -s` adds the latter).
- `#!/usr/bin/env bash`, `set -euo pipefail`, tabs. Shellcheck-clean with `.shellcheckrc`.
  CI lints with Ubuntu 24.04's shellcheck 0.9.0, which flags `A && B || C` (SC2015) where newer
  releases stay quiet: write an `if`. Without a local shellcheck, lint with the same version via
  `docker run --rm -v "$PWD:/mnt" -w /mnt koalaman/shellcheck:v0.9.0 -x <files>`.
- tmux format output is parsed by having tmux emit tabs and `tr '\t' '\037'` before `IFS=$'\x1f' read`;
  tmux escapes control characters in formats and bash collapses consecutive tabs. Always call
  tmux through `tmux_cmd` (it passes `-u`): a client without a UTF-8 locale gets tabs as `_`.
- Never pipe `ai-revive` or `tmux` output into `grep -q` in tests (SIGPIPE + pipefail); use the
  harness's `has PATTERN CMD...` or capture into a variable.
- `wait_until SECONDS 'condition'` takes a string evaluated each poll.
- The checkout, a TPM clone and `/usr/share/ai-revive` have the same layout
  (`ai-revive.tmux`, `lib/`, `resumers/`); `bin/ai-revive` finds `AI_REVIVE_HOME` from its own path.
- Match Claude panes on `@window.%pane` only; the session-name prefix in
  `~/.claude/sessions/<pid>.json` goes stale when byobu re-attaches.

- Agent resumers without a pane registry (codex, gemini, copilot) use `lib/agents.sh` and try, in
  order: a session file the process holds open; `agent_resume_arg` (a UUID after `--resume` or
  `resume` on its command line); `agent_pick` (session created soonest after the process started,
  else newest modified); the command line. The resume argument must come before `agent_pick`:
  a restore starts all agents within milliseconds, which start times cannot tell apart.
  `agent_find_process` matches the whole command line, so node-based CLIs are found. Their fakes
  in `tests/fakes/` write the tools' documented files and block as `node <script> <args>`,
  keeping the arguments on the command line as the real CLIs do (`exec -a x sleep` loses them).

## Verifying a change

```bash
make lint
make test                                  # all tests, private tmux servers
make audit                                 # privacy audit of the whole history (before any public push)
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
- "Is the pane at its prompt" is `pane_idle` (the pane's root process has no children), never a
  list of shell names: it works for any shell and is false while byobu-shell prints its motd.
- The server's only session is taken over by the *first* missing saved session (decided once in
  `restore_from_file`); later missing sessions are created. A pre-existing session's single
  window is a placeholder only if idle; a taken-over session's always is. The placeholder is
  removed at the end only if idle and not the pane the restore itself runs in.
- Snapshot file names carry milliseconds and are written under a directory lock; a settle save
  is never spawned for `--layout-only` (it would record the scratch server).
- A running restore holds `flock` on `restore.lock` (released by the kernel if it dies); saves
  check `restore_in_progress`, never a pid file.
- tmux does not scale a layout string to the window size (every pane shrinks by the same absolute
  amount). Always apply saved layouts through `layout_scale` (`lib/layout.sh` explains it).
