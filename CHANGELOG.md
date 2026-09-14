# Changelog

## 0.1.0 — 2026-09-09

Initial release.

- `save` / `restore` of tmux sessions, windows, panes, names, layouts and directories, with
  one session per byobu session group and idempotent restores. Layouts are rescaled
  proportionally to the window size at restore time (tmux itself does not scale them).
- Resumers: Claude Code by session id (via `~/.claude/sessions`), OpenAI Codex CLI, Gemini CLI
  and GitHub Copilot CLI by the session file their process holds open, the session id on their
  command line (how a restore relaunches them) or the session file created after they started
  (written from the published formats, tested against fakes), ssh by command line, whitelist.
- Auto-save through tmux hooks (debounced) and a systemd user timer; best-effort shutdown save;
  `ai-revive reboot` / `shutdown` for an exact snapshot.
- Auto-restore at server start (`AUTO_RESTORE=reboot|always|never`), once per server. A
  snapshot from a previous boot is protected from being overwritten until a restore ran.
- `enable` / `disable` for byobu (`$BYOBU_CONFIG_DIR/.tmux.conf`) and plain tmux; TPM entry point.
- Works without a UTF-8 locale (bare systemd units, containers): tmux is always called with `-u`.
- Debian packaging, man pages, test-suite on private tmux servers.
