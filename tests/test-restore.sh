#!/usr/bin/env bash
# restore: a snapshot taken on server A is rebuilt on a fresh server B (names, panes, cwds, layouts).
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

mkdir -p "$HOME/proj-a" "$HOME/proj-b"
fresh_server work
T rename-window -t work:0 edit
T new-window -t work -n shells -c "$HOME/proj-a"
T split-window -t work:1 -v -c "$HOME/proj-b"
T split-window -t work:1 -h -c "$HOME"
T select-layout -t work:1 main-vertical
T new-window -t work -n three -c "$HOME/proj-b"
T select-window -t work:1
"$AR" save
before=$(T list-panes -s -t work -F '#{window_index}:#{window_name}:#{pane_index}:#{pane_current_path}')
layout_before=$(T display -p -t work:1 '#{window_layout}')
kill_server

fresh_server 0
"$AR" restore
T has-session -t work || fail "session not restored"
T has-session -t 0 2>/dev/null && fail "fresh placeholder session should have been renamed"
after=$(T list-panes -s -t work -F '#{window_index}:#{window_name}:#{pane_index}:#{pane_current_path}')
assert_eq "$after" "$before" "windows/panes/cwds"
assert_eq "$(layout_shape "$(T display -p -t work:1 "#{window_layout}")")" "$(layout_shape "$layout_before")" "layout shape"
assert_eq "$(T display -p -t work '#{window_index}')" 1 "active window"
assert_eq "$(T display -p -t work:1 '#{automatic-rename}')" 0 "manual window name keeps automatic-rename off"

# idempotent: a second restore changes nothing
"$AR" restore
assert_eq "$(T list-panes -s -t work -F x | wc -l)" 5 "pane count after second restore"
assert_eq "$(T list-sessions -F x | wc -l)" 1 "session count after second restore"

# a program started in the placeholder window survives the restore (moved after the last window)
kill_server
fresh_server 0
type_in 0:0 "tail -f /dev/null"
wait_until 5 '[ "$(pane_cmd 0:0)" = tail ]' || fail "tail not running"
"$AR" restore
assert_eq "$(T list-windows -t work -F '#{window_index}' | tr '\n' ' ')" "0 1 2 3 " "restored windows plus the kept one"
assert_eq "$(pane_cmd work:3)" tail "kept window still runs the program"

# dry run on a fresh server creates nothing and prints the plan
kill_server
fresh_server 0
out=$("$AR" restore --dry-run)
echo "$out" | grep -q "would rename session '0' to 'work'" || fail "dry-run plan: $out"
echo "$out" | grep -q "window 1 'shells' (3 panes)" || fail "dry-run window line: $out"
assert_eq "$(T list-windows -t 0 -F x | wc -l)" 1 "dry run must not create windows"
# a smaller terminal gets proportional splits: 30:19 rows saved at 200x50 -> 18:11 at 100x30
kill_server
fresh_server big
T split-window -t big:0 -v -c "$HOME"
T resize-pane -t big:0.0 -y 30
assert_eq "$(T display -p -t big:0.0 '#{pane_height}')" 30 "setup"
"$AR" save
kill_server
fresh_server 0 100 30
"$AR" restore --layout-only
assert_eq "$(T list-panes -t big:0 -F '#{pane_height}' | tr '\n' ' ')" "18 11 " "scaled pane heights"
# a window too small for the saved panes falls back to tiled instead of failing
kill_server
fresh_server 0 100 4
"$AR" restore --layout-only
assert_eq "$(T list-panes -t big:0 -F x | wc -l)" 2 "panes still created when the layout does not fit"
# a snapshot with two sessions restores into a fresh server as two sessions (not merged)
kill_server
fresh_server alpha
T new-window -t alpha -n a2
T new-session -d -s beta -x 200 -y 50 -c "$HOME"
T new-window -t beta -n b2
"$AR" save
assert_json "$(last_snapshot)" '.sessions | length == 2'
kill_server
fresh_server 0
"$AR" restore
assert_eq "$(T list-sessions -F '#{session_name}' | sort | tr '\n' ' ')" "alpha beta " "both sessions"
assert_eq "$(T list-windows -t alpha -F x | wc -l)" 2 "alpha windows"
assert_eq "$(T list-windows -t beta -F x | wc -l)" 2 "beta windows"

# a one-window snapshot whose program is running is not restored twice
kill_server
fresh_server solo
type_in solo:0 "tail -f /dev/null"
wait_until 5 '[ "$(pane_cmd solo:0)" = tail ]' || fail "tail not running"
TWR_RESUME_COMMANDS="tail" "$AR" save
kill_server
fresh_server 0
"$AR" restore
wait_until 10 '[ "$(pane_cmd solo:0)" = tail ]' || fail "tail not relaunched"
"$AR" restore
sleep 1
assert_eq "$(T list-panes -s -t solo -F x | wc -l)" 1 "second restore must not duplicate the window"

# `tmux-workspace-resume restore` typed into the fresh window: no stall, that window is kept, others restored
kill_server
fresh_server 0
start=$(date +%s)
type_in 0:0 "$AR restore"
wait_until 20 'T has-session -t solo 2>/dev/null && [ "$(pane_cmd solo:0)" = tail ]' || fail "restore from inside the pane did not finish"
[ $(( $(date +%s) - start )) -lt 8 ] || fail "restore from inside the pane stalled"
assert_eq "$(T list-windows -t solo -F '#{window_index}' | tr '\n' ' ')" "0 1 " "restored window plus the one the restore ran in"
echo "ok"
