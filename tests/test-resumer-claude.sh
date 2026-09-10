#!/usr/bin/env bash
# claude resumer: two claude panes in the same directory get their own session ids, restore
# relaunches each with --resume <id> in the right cwd; a claude without a record falls back to --continue.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

mkdir -p "$HOME/proj"
fresh_server dev
type_in dev:0 "cd $HOME/proj && claude"
T split-window -t dev:0 -h -c "$HOME/proj"
type_in dev:0.1 "claude --resume 11111111-2222-3333-4444-555555555555"
wait_until 5 '[ "$(find "$HOME/.claude/sessions" -name "*.json" 2>/dev/null | wc -l)" = 2 ]' || fail "fake claudes did not register"
wait_until 5 '[ "$(pane_cmd dev:0.0)" = claude ]' || fail "pane 0 not running claude"

"$AR" save
snap=$(last_snapshot)
assert_json "$snap" '[.sessions[0].windows[0].panes[] | select(.resumer == "claude")] | length == 2'
assert_json "$snap" '.sessions[0].windows[0].panes[1].restore_cmd == "claude --resume 11111111-2222-3333-4444-555555555555"'
assert_json "$snap" '.sessions[0].windows[0].panes[0].restore_cmd | test("^claude --resume [0-9a-f-]{36}$")'
assert_json "$snap" '.sessions[0].windows[0].panes[0].restore_cmd != .sessions[0].windows[0].panes[1].restore_cmd'
assert_json "$snap" ".sessions[0].windows[0].panes[0].restore_cwd == \"$HOME/proj\""
assert_json "$snap" '.sessions[0].windows[0].panes[0].meta.name == "fake-session"'
id0=$(jq -r '.sessions[0].windows[0].panes[0].meta.sessionId' "$snap")

kill_server
rm -f "$FAKE_LOG"/claude.*.args
fresh_server 0
"$AR" restore
wait_until 10 '[ "$(find "$FAKE_LOG" -name "claude.*.args" | wc -l)" = 2 ]' || fail "restored claudes did not start"
grep -lx "$id0" "$FAKE_LOG"/claude.*.args >/dev/null || fail "pane 0 was not resumed with $id0"
grep -lx "11111111-2222-3333-4444-555555555555" "$FAKE_LOG"/claude.*.args >/dev/null || fail "pane 1 was not resumed with its id"
for f in "$FAKE_LOG"/claude.*.args; do assert_eq "$(head -1 "$f")" "--resume" "first arg"; done
# the restored claudes registered from the right directory
wait_until 5 '[ "$(jq -r .cwd "$HOME"/.claude/sessions/*.json | sort -u)" = "$HOME/proj" ]' || fail "restored claude cwd"

# fallback: a claude that never registered is relaunched with the command line it was started with
kill_server
rm -rf "$HOME/.claude/sessions" "$(snapshot_dir)"
fresh_server dev
type_in dev:0 "cd $HOME/proj && FAKE_CLAUDE_NO_REGISTRY=1 claude"
wait_until 5 '[ "$(pane_cmd dev:0)" = claude ]' || fail "unregistered claude not running"
"$AR" save
snap=$(last_snapshot)
assert_json "$snap" '.sessions[0].windows[0].panes[0].restore_cmd | startswith("claude")' "argv fallback re-emits the command line"
assert_json "$snap" '.sessions[0].windows[0].panes[0].restore_cmd | contains("--continue") | not' "no --continue guess"
assert_json "$snap" '.sessions[0].windows[0].panes[0].meta.fallback == "argv"'
echo ok
