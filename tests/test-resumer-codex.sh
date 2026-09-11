#!/usr/bin/env bash
# codex resumer: the session is found through the newest rollout file in the process's directory;
# two panes in one directory keep distinct sessions; restore relaunches `codex resume <id>`;
# without a rollout file the typed command line comes back.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

mkdir -p "$HOME/proj"
fresh_server dev
type_in dev:0 "cd $HOME/proj && codex"
sleep 2.5                                   # session timestamps have second resolution
T split-window -t dev:0 -h -c "$HOME/proj"
type_in dev:0.1 "codex resume 22222222-2222-2222-2222-222222222222"
wait_until 5 '[ "$(pane_cmd dev:0.0)" = codex ] && [ "$(pane_cmd dev:0.1)" = codex ]' || fail "fake codex not running"
sleep 1
"$AR" save
snap=$(last_snapshot)
assert_json "$snap" '[.sessions[0].windows[0].panes[] | select(.resumer == "codex")] | length == 2'
assert_json "$snap" '.sessions[0].windows[0].panes[1].restore_cmd == "codex resume 22222222-2222-2222-2222-222222222222"'
assert_json "$snap" '.sessions[0].windows[0].panes[0].restore_cmd | test("^codex resume [0-9a-f-]{36}$")'
assert_json "$snap" '.sessions[0].windows[0].panes[0].restore_cmd != .sessions[0].windows[0].panes[1].restore_cmd'
assert_json "$snap" '.sessions[0].windows[0].panes[0].meta.matched_by == "started-after-process"'
id0=$(jq -r '.sessions[0].windows[0].panes[0].meta.sessionId' "$snap")

kill_server; rm -f "$FAKE_LOG"/codex.*.args
fresh_server 0
"$AR" restore
wait_until 10 '[ "$(find "$FAKE_LOG" -name "codex.*.args" | wc -l)" = 2 ]' || fail "restored codex did not start"
grep -lx "$id0" "$FAKE_LOG"/codex.*.args >/dev/null || fail "pane 0 not resumed with $id0"
for f in "$FAKE_LOG"/codex.*.args; do assert_eq "$(head -1 "$f")" resume "first arg"; done

# fallback: no rollout file -> the typed command line, no session id
kill_server; rm -rf "$HOME/.codex" "$(snapshot_dir)"
fresh_server dev
type_in dev:0 "cd $HOME/proj && FAKE_NO_SESSION=1 codex --model o3"
wait_until 5 '[ "$(pane_cmd dev:0)" = codex ]' || fail "codex not running"
"$AR" save
assert_json "$(last_snapshot)" '.sessions[0].windows[0].panes[0].restore_cmd == "codex infinity" and .sessions[0].windows[0].panes[0].meta.matched_by == "argv"'
echo ok
