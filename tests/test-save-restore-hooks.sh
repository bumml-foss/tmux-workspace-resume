#!/usr/bin/env bash
# HOOK_POST_SAVE / HOOK_PRE_RESTORE / HOOK_POST_RESTORE run with the snapshot as $1, before and
# after the restore changes the server; a failing hook does not stop the save.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

windows='$(tmux -L "$TWR_TMUX_SOCKET_NAME" list-windows -a | wc -l)'
export TWR_HOOK_POST_SAVE='echo "post-save $(basename "$1")" >> "$TMP/hooks.log"'
export TWR_HOOK_PRE_RESTORE="echo \"pre-restore $windows \$(basename \"\$1\")\" >> \"\$TMP/hooks.log\""
export TWR_HOOK_POST_RESTORE="echo \"post-restore $windows\" >> \"\$TMP/hooks.log\""

fresh_server main
T new-window -t main
T new-window -t main
"$AR" -q save
snap=$(basename "$(last_snapshot)")
"$AR" -q save
assert_eq "$(cat "$TMP/hooks.log")" "post-save $snap
post-save $snap" "post-save after a new and after an unchanged save"

kill_server
fresh_server 0
: > "$TMP/hooks.log"
"$AR" -q restore --dry-run > /dev/null
assert_eq "$(cat "$TMP/hooks.log")" "" "a dry run runs no hooks"
"$AR" -q restore
assert_eq "$(cat "$TMP/hooks.log")" "pre-restore 1 $snap
post-restore 3" "restore hooks see the server before and after"

TWR_HOOK_POST_SAVE='exit 3' "$AR" -q save --force
assert_eq "$(find "$(snapshot_dir)" -maxdepth 1 -name '2*.json' -type f | wc -l)" 2 "a failing hook does not stop the save"
has 'HOOK_POST_SAVE exited with 3' cat "$XDG_STATE_HOME/tmux-workspace-resume/tmux-workspace-resume.log" ||
	fail "a failing hook is logged"
echo ok
