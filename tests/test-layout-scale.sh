#!/usr/bin/env bash
# layout_scale: identity is exact (checksum included), other sizes keep the proportions, nested
# containers survive, and tmux accepts the result.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
. "$REPO/lib/layout.sh"

# real layouts captured from tmux 3.4
big='09fa,382x93,0,0[382x67,0,0,13,382x25,0,68,33]'
nested='acd9,190x45,0,0[190x32,0,0{95x32,0,0,14,94x32,96,0,39},190x12,0,33,1]'
single='c0c0,190x45,0,0,3'

assert_eq "$(layout_scale "$big" 382 93)" "$big" "identity"
assert_eq "$(layout_scale "$nested" 190 45)" "$nested" "identity nested"
assert_eq "$(layout_scale "$single" 190 45)" "$single" "identity single"
assert_eq "$(layout_scale "$single" 80 24 | cut -d, -f2-)" "80x24,0,0,3" "single pane resized"
# 67:25 of 93 rows -> 190x45: 33 + 1 separator + 11 = 45
assert_eq "$(layout_scale "$big" 190 45 | cut -d, -f2-)" "190x45,0,0[190x33,0,0,13,190x11,0,34,33]" "proportional shrink"
# growing back keeps the ratio (33:11 of 44 usable rows -> 92 usable: 69 + 1 + 23)
assert_eq "$(layout_scale "$(layout_scale "$big" 190 45)" 382 93 | cut -d, -f2-)" "382x93,0,0[382x69,0,0,13,382x23,0,70,33]" "proportional grow"
# nested: 95:94 of 189 usable cols -> 99: 50 + 1 + 49 ; 32:12 of 44 usable rows -> 29: 22 + 1 + 7
assert_eq "$(layout_scale "$nested" 100 30 | cut -d, -f2-)" "100x30,0,0[100x22,0,0{50x22,0,0,14,49x22,51,0,39},100x7,0,23,1]" "nested"
# a pane never shrinks below one row/column
out=$(layout_scale "$big" 190 3 | cut -d, -f2-)
assert_eq "$out" "190x3,0,0[190x1,0,0,13,190x1,0,2,33]" "minimum size"
# garbage is rejected
layout_scale "nope" 10 10 >/dev/null 2>&1 && fail "garbage accepted"

# tmux accepts the scaled string: three panes restored on a 100x30 server from a 190x45 layout
T new-session -d -s l -x 100 -y 30
T split-window -t l:0 -v; T split-window -t l:0.0 -h
scaled=$(layout_scale "$nested" 100 30)
T select-layout -t l:0 "$scaled" || fail "tmux rejected: $scaled"
assert_eq "$(layout_shape "$(T display -p -t l:0 '#{window_layout}')")" "$(layout_shape "$scaled")" "applied layout"
echo ok

# end to end: a 30:19 split saved at 200x50 restores as 18:11 at 100x30, not as 28:1
kill_server
fresh_server big
T split-window -t big:0 -v -c "$HOME"
T resize-pane -t big:0.0 -y 30
assert_eq "$(T display -p -t big:0.0 '#{pane_height}')" 30 "setup"
"$AR" save
kill_server
T new-session -d -s 0 -x 100 -y 30
"$AR" restore --layout-only
assert_eq "$(T list-panes -t big:0 -F '#{pane_height}' | tr '\n' ' ')" "18 11 " "scaled pane heights"
echo ok
