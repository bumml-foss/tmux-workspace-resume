#!/usr/bin/env bash
# agy resumer: a live session is found through the presence lockfile the process holds open, else
# the conversation id on its command line, else history.jsonl for the process's workspace; restore
# relaunches `agy --conversation <id>`, and restored panes keep their own conversations; without
# session files or an id, the typed command line comes back.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

mkdir -p "$HOME/proj"
fresh_server dev
type_in dev:0 "cd $HOME/proj && agy"
wait_until 5 '[ "$(pane_cmd dev:0)" = agy-fake ]' || fail "fake agy not running"
T split-window -t dev:0 -h -c "$HOME/proj"
type_in dev:0.1 "agy --conversation=66666666-6666-6666-6666-666666666666"
wait_until 5 '[ "$(pane_cmd dev:0.1)" = agy-fake ]' || fail "second fake agy not running"
"$AR" save
snap=$(last_snapshot)
assert_json "$snap" '[.sessions[0].windows[0].panes[] | select(.resumer == "agy")] | length == 2'
assert_json "$snap" '.sessions[0].windows[0].panes[1].restore_cmd == "agy --conversation 66666666-6666-6666-6666-666666666666"'
assert_json "$snap" '.sessions[0].windows[0].panes[1].meta.matched_by == "open-file"'
assert_json "$snap" '.sessions[0].windows[0].panes[0].restore_cmd | test("^agy --conversation [0-9a-f-]{36}$")'
assert_json "$snap" '.sessions[0].windows[0].panes[0].restore_cmd != .sessions[0].windows[0].panes[1].restore_cmd'
assert_json "$snap" '.sessions[0].windows[0].panes[0].meta.matched_by == "open-file"'
id0=$(jq -r '.sessions[0].windows[0].panes[0].meta.sessionId' "$snap")

kill_server; rm -f "$FAKE_LOG"/agy.*.args
fresh_server 0
"$AR" restore
wait_until 10 '[ "$(find "$FAKE_LOG" -name "agy.*.args" | wc -l)" = 2 ]' || fail "restored agy did not start"
grep -lx "$id0" "$FAKE_LOG"/agy.*.args >/dev/null || fail "pane 0 not resumed with $id0"
for f in "$FAKE_LOG"/agy.*.args; do assert_eq "$(head -1 "$f")" "--conversation" "first arg"; done
wait_until 5 '[ "$(pane_cmd dev:0.0)" = agy-fake ] && [ "$(pane_cmd dev:0.1)" = agy-fake ]' || fail "restored agy not running"
assert_json "$(saved_snapshot)" "[.sessions[0].windows[0].panes[].meta.sessionId] == [\"$id0\", \"66666666-6666-6666-6666-666666666666\"]" "restored panes keep their own conversations"

# history.jsonl fallback when no lockfile/db is held open; another workspace's history is ignored
kill_server; rm -rf "$HOME/.gemini" "$(snapshot_dir)"; mkdir -p "$HOME/other"
fresh_server dev
type_in dev:0 "cd $HOME/proj && FAKE_NO_OPEN=1 agy"
wait_until 5 '[ "$(pane_cmd dev:0)" = agy-fake ]' || fail "history-fallback agy not running"
sleep 1
T new-window -t dev: -c "$HOME/other"
type_in dev:1 "FAKE_NO_SESSION=1 agy"
wait_until 5 '[ "$(pane_cmd dev:1)" = agy-fake ]' || fail "other-workspace agy not running"
"$AR" save
assert_json "$(last_snapshot)" '.sessions[0].windows[0].panes[0].meta.matched_by == "started-after-process"'
assert_json "$(last_snapshot)" '.sessions[0].windows[1].panes[0].meta.matched_by == "argv"' "other workspace history must not be matched"

# without session files: --conversation on the command line, else the typed command line
kill_server; rm -rf "$HOME/.gemini" "$(snapshot_dir)"
fresh_server dev
type_in dev:0 "cd $HOME/proj && FAKE_NO_SESSION=1 agy --model gemini-3"
wait_until 5 '[ "$(pane_cmd dev:0)" = agy-fake ]' || fail "argv-fallback agy not running"
T new-window -t dev: -c "$HOME/proj"
type_in dev:1 "FAKE_NO_SESSION=1 agy --conversation=77777777-7777-7777-7777-777777777777"
wait_until 5 '[ "$(pane_cmd dev:1)" = agy-fake ]' || fail "resume-arg agy not running"
"$AR" save
assert_json "$(last_snapshot)" '.sessions[0].windows[0].panes[0].restore_cmd == "agy --model gemini-3" and .sessions[0].windows[0].panes[0].meta.matched_by == "argv"'
assert_json "$(last_snapshot)" '.sessions[0].windows[1].panes[0].restore_cmd == "agy --conversation 77777777-7777-7777-7777-777777777777" and .sessions[0].windows[1].panes[0].meta.matched_by == "resume-argument"'
echo ok
