#!/usr/bin/env bash
# copilot resumer: the session is found through the events file the process holds open, else the
# id on its command line; restore relaunches `copilot --resume <id>`; with neither, the typed
# command line comes back.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

mkdir -p "$HOME/proj"
fresh_server dev
type_in dev:0 "cd $HOME/proj && copilot"
wait_until 5 '[ "$(pane_cmd dev:0)" = node ]' || fail "fake copilot not running"
T split-window -t dev:0 -h -c "$HOME/proj"
type_in dev:0.1 "copilot --resume=44444444-4444-4444-4444-444444444444"
wait_until 5 '[ "$(pane_cmd dev:0.1)" = node ]' || fail "second fake copilot not running"
"$AR" save
snap=$(last_snapshot)
assert_json "$snap" '[.sessions[0].windows[0].panes[] | select(.resumer == "copilot")] | length == 2'
assert_json "$snap" '.sessions[0].windows[0].panes[1].restore_cmd == "copilot --resume 44444444-4444-4444-4444-444444444444"'
assert_json "$snap" '.sessions[0].windows[0].panes[0].restore_cmd | test("^copilot --resume [0-9a-f-]{36}$")'
assert_json "$snap" '.sessions[0].windows[0].panes[0].meta.matched_by == "open-file"'
id0=$(jq -r '.sessions[0].windows[0].panes[0].meta.sessionId' "$snap")

kill_server; rm -f "$FAKE_LOG"/copilot.*.args
fresh_server 0
"$AR" restore
wait_until 10 '[ "$(find "$FAKE_LOG" -name "copilot.*.args" | wc -l)" = 2 ]' || fail "restored copilot did not start"
grep -lx "$id0" "$FAKE_LOG"/copilot.*.args >/dev/null || fail "pane 0 not resumed with $id0"

# without session directories: the id on the command line, else the typed command line
kill_server; rm -rf "$HOME/.copilot" "$(snapshot_dir)"
fresh_server dev
type_in dev:0 "cd $HOME/proj && FAKE_NO_SESSION=1 copilot"
wait_until 5 '[ "$(pane_cmd dev:0)" = node ]' || fail "copilot not running"
T new-window -t dev: -c "$HOME/proj"
type_in dev:1 "FAKE_NO_SESSION=1 copilot --resume=55555555-5555-5555-5555-555555555555"
wait_until 5 '[ "$(pane_cmd dev:1)" = node ]' || fail "resumed copilot not running"
"$AR" save
assert_json "$(last_snapshot)" '.sessions[0].windows[0].panes[0].restore_cmd == "copilot" and .sessions[0].windows[0].panes[0].meta.matched_by == "argv"'
assert_json "$(last_snapshot)" '.sessions[0].windows[1].panes[0].restore_cmd == "copilot --resume 55555555-5555-5555-5555-555555555555" and .sessions[0].windows[1].panes[0].meta.matched_by == "resume-argument"'
echo ok
