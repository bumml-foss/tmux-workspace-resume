#!/usr/bin/env bash
# save: windows, names, cwds, layout, boot_id, last.json symlink, pruning.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

mkdir -p "$HOME/proj-a" "$HOME/proj-b"
fresh_server main
T rename-window -t main:0 alpha
T new-window -t main -n beta -c "$HOME/proj-a"
T split-window -t main:1 -h -c "$HOME/proj-b"
T new-window -t main -c "$HOME/proj-b"          # automatic name

"$AR" save
snap=$(last_snapshot)
[ -f "$snap" ] || fail "no snapshot written"
assert_json "$snap" '.version == 1'
assert_json "$snap" ".boot_id == \"$(cat /proc/sys/kernel/random/boot_id)\""
assert_json "$snap" '.sessions | length == 1'
assert_json "$snap" '.sessions[0].name == "main"'
assert_json "$snap" '.sessions[0].windows | length == 3'
assert_json "$snap" '.sessions[0].windows[0].name == "alpha" and .sessions[0].windows[0].automatic_rename == false'
assert_json "$snap" '.sessions[0].windows[1].name == "beta" and (.sessions[0].windows[1].panes | length) == 2'
assert_json "$snap" ".sessions[0].windows[1].panes[0].cwd == \"$HOME/proj-a\""
assert_json "$snap" ".sessions[0].windows[1].panes[1].cwd == \"$HOME/proj-b\""
assert_json "$snap" '.sessions[0].windows[2].automatic_rename == true'
assert_json "$snap" '.sessions[0].windows[1].layout | test("^[0-9a-f]{4},")'
assert_json "$snap" '.sessions[0].active_window == 2'
assert_json "$snap" '.sessions[0].windows[0].width == 200 and .sessions[0].windows[0].height == 50'
assert_json "$snap" '[.sessions[].windows[].panes[] | select(.restore_cmd != null)] | length == 0'

# pruning keeps KEEP_SNAPSHOTS files
for _ in 1 2 3 4; do sleep 1; AI_REVIVE_KEEP_SNAPSHOTS=3 "$AR" -q save --force; done
n=$(find "$(snapshot_dir)" -maxdepth 1 -name '*.json' -type f | wc -l)
assert_eq "$n" 3 "pruned to KEEP_SNAPSHOTS"
[ -L "$(snapshot_dir)/last.json" ] || fail "last.json is not a symlink"

# list prints one line per snapshot with the summary
out=$("$AR" list)
echo "$out" | grep -q '1 session(s), 3 window(s), 4 pane(s)' || fail "list summary: $out"
assert_eq "$(echo "$out" | grep -c '(last)')" 1 "exactly one (last) marker"
echo "ok"
