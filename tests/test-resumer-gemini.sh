#!/usr/bin/env bash
# gemini resumer: the session is found through the newest chat file in the project hash dir of
# the process's cwd; node-style command lines are recognised; restore passes --resume <id>.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

mkdir -p "$HOME/proj"
fresh_server dev
type_in dev:0 "cd $HOME/proj && gemini"
sleep 2.5                                   # session timestamps have second resolution
T split-window -t dev:0 -h -c "$HOME/proj"
type_in dev:0.1 "FAKE_NODE_STYLE=1 gemini --resume 33333333-3333-3333-3333-333333333333"
wait_until 5 '[ "$(pane_cmd dev:0.0)" = gemini ] && [ "$(pane_cmd dev:0.1)" = index.js ]' || fail "fake gemini not running"
sleep 1
"$AR" save
snap=$(last_snapshot)
assert_json "$snap" '[.sessions[0].windows[0].panes[] | select(.resumer == "gemini")] | length == 2' "node-style process recognised too"
assert_json "$snap" '.sessions[0].windows[0].panes[1].restore_cmd == "gemini --resume 33333333-3333-3333-3333-333333333333"'
assert_json "$snap" '.sessions[0].windows[0].panes[0].restore_cmd | test("^gemini --resume [0-9a-f-]{36}$")'
assert_json "$snap" '.sessions[0].windows[0].panes[0].meta.matched_by == "started-after-process"'
id0=$(jq -r '.sessions[0].windows[0].panes[0].meta.sessionId' "$snap")

kill_server; rm -f "$FAKE_LOG"/gemini.*.args
fresh_server 0
"$AR" restore
wait_until 10 '[ "$(find "$FAKE_LOG" -name "gemini.*.args" | wc -l)" = 2 ]' || fail "restored gemini did not start"
grep -lx "$id0" "$FAKE_LOG"/gemini.*.args >/dev/null || fail "pane 0 not resumed with $id0"

# a chat file of another project directory is not picked up
kill_server; rm -rf "$HOME/.gemini" "$(snapshot_dir)"; mkdir -p "$HOME/other"
fresh_server dev
type_in dev:0 "cd $HOME/other && gemini"
wait_until 5 '[ "$(pane_cmd dev:0)" = gemini ]' || fail "gemini not running"
sleep 1
T new-window -t dev: -c "$HOME/proj"
type_in dev:1 "FAKE_NO_SESSION=1 gemini"
wait_until 5 '[ "$(pane_cmd dev:1)" = gemini ]' || fail "second gemini not running"
"$AR" save
assert_json "$(last_snapshot)" '.sessions[0].windows[0].panes[0].meta.matched_by == "started-after-process"'
assert_json "$(last_snapshot)" '.sessions[0].windows[1].panes[0].meta.matched_by == "argv"' "other project's chat must not be matched"
echo ok
