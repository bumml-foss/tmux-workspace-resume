# Changelog

## Unreleased

- Snapshot names come from a single clock reading instead of `date`: the Rust coreutils `date` of
  Ubuntu 26.04 can pair the milliseconds with the previous second, so names did not always sort by
  age (and `test-auto-restore.sh` failed intermittently).
- `enable` and `status` accept a degraded systemd user manager (one failed unit anywhere); they used
  to report "no systemd user session" and skip the timer.
- `save` writes no new snapshot when the workspace would restore the same way (pane titles, pane
  commands and automatic window names are ignored); it only refreshes the newest snapshot's mtime,
  so idle saves no longer push older states out of `KEEP_SNAPSHOTS`. `--force` still writes.

## 0.2.0 — 2026-10-09

- Renamed from ai-revive to tmux-workspace-resume: the command (and `byobu-tmux-workspace-resume`),
  the Debian package, man pages, systemd units, the config, state and runtime directories, the
  `.tmux.conf` marker block and the log prefix. Environment variables use the prefix `TWR_`
  (resumers read `$TWR_PANE_PID`, `$TWR_CWD`, ...). There is no automatic migration: run the old
  `ai-revive disable`, move `~/.config/ai-revive` and `~/.local/state/ai-revive` to the new name,
  then run `tmux-workspace-resume enable`.
- The README covers install and use only; development notes moved to `CONTRIBUTING.md`.

## 0.1.0 — 2026-09-14

Initial release.

- `save` / `restore` of tmux sessions, windows, panes, names, layouts and directories, with
  one session per byobu session group and idempotent restores. Layouts are rescaled
  proportionally to the window size at restore time (tmux itself does not scale them).
- Resumers: Claude Code by session id (via `~/.claude/sessions`), OpenAI Codex CLI, Gemini CLI
  and GitHub Copilot CLI by the session file their process holds open, the session id on their
  command line (how a restore relaunches them) or the session file created after they started
  (written from the published formats, tested against fakes), ssh by command line, whitelist.
- Auto-save through tmux hooks (debounced) and a systemd user timer; best-effort shutdown save;
  `tmux-workspace-resume reboot` / `shutdown` for an exact snapshot.
- Auto-restore at server start (`AUTO_RESTORE=reboot|always|never`), once per server. A
  snapshot from a previous boot is protected from being overwritten until a restore ran.
- `enable` / `disable` for byobu (`$BYOBU_CONFIG_DIR/.tmux.conf`) and plain tmux; TPM entry point.
- Works without a UTF-8 locale (bare systemd units, containers): tmux is always called with `-u`.
- Debian packaging, man pages, test-suite on private tmux servers.
