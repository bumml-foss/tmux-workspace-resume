#!/usr/bin/env bash
# End to end: a tmux server started the way byobu starts one (config file that runs ai-revive.tmux,
# a single placeholder window running the shell) restores a previous-boot snapshot on its own:
# the placeholder session is renamed, windows/panes come back, programs are relaunched, hooks are
# installed, and the whole thing happens exactly once per server.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

export AI_REVIVE_RESUME_COMMANDS="tail"
mkdir -p "$HOME/work"

# 1. the workspace to be revived: 2 windows, a whitelisted program, a claude
fresh_server 0
T rename-window -t 0:0 code
type_in 0:0 "cd $HOME/work && claude"
T new-window -t 0: -n logs -c "$HOME/work"
type_in 0:1 "tail -f /dev/null"
T split-window -t 0:1 -v -c "$HOME"
wait_until 5 '[ "$(pane_cmd 0:0)" = claude ] && [ "$(pane_cmd 0:1.0)" = tail ]' || fail "programs not running"
"$AR" save
id=$(jq -r '.sessions[0].windows[0].panes[0].meta.sessionId' "$(last_snapshot)")
if [ -z "$id" ] || [ "$id" = null ]; then fail "no claude session id captured"; fi
kill_server
rm -f "$FAKE_LOG"/claude.*.args
# pretend the machine rebooted
jq '.boot_id = "00000000-0000-0000-0000-000000000000"' "$(last_snapshot)" > "$(snapshot_dir)/reboot.json"
ln -sfn reboot.json "$(snapshot_dir)/last.json"

# 2. the byobu-style start: config runs the plugin, one placeholder window with a login shell
conf=$TMP/tmux.conf
printf 'run-shell -b "%s/ai-revive.tmux"\n' "$REPO" > "$conf"
shell=$(command -v byobu-shell || command -v bash)
tmux -L "$AI_REVIVE_TMUX_SOCKET_NAME" -f "$conf" new-session -d -x 200 -y 50 -n - "$shell"

wait_until 15 '[ "$(T list-windows -t 0 -F "#{window_name}" 2>/dev/null | tr "\n" " ")" = "code logs " ]' || fail "windows not restored: $(T list-windows -a 2>&1)"
assert_eq "$(T list-windows -t 0 -F '#{window_index}:#{window_name}:#{window_panes}' | tr '\n' ' ')" "0:code:1 1:logs:2 " "windows"
wait_until 15 '[ "$(pane_cmd 0:0)" = claude ]' || fail "claude not relaunched"
wait_until 15 '[ "$(pane_cmd 0:1.0)" = tail ]' || fail "tail not relaunched"
wait_until 5 '[ -n "$(cat "$FAKE_LOG"/claude.*.args 2>/dev/null)" ]' || fail "claude args not recorded"
grep -qx "$id" "$FAKE_LOG"/claude.*.args || fail "claude was not resumed with $id"
assert_eq "$(T display -p -t 0:1.0 '#{pane_current_path}')" "$HOME/work" "pane cwd"
wait_until 5 '[ "$(T show-hooks -g | grep -c "\[900\]")" = 10 ]' || fail "hooks not installed at server start"
ls "$XDG_RUNTIME_DIR"/ai-revive/restored-*-"$(T display -p '#{pid}')" >/dev/null 2>&1 || fail "restored marker missing"

# 3. a second client attaching through a grouped session (what byobu does) restores nothing again
T new-session -d -t 0 -s 0-2
sleep 2
assert_eq "$(T list-windows -t 0 -F x | wc -l)" 2 "no double restore"
echo ok
