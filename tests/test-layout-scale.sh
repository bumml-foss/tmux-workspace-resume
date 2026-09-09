#!/usr/bin/env bash
# layout_scale: identity is exact (checksum included), other sizes keep the proportions, nested
# containers survive, tiny targets stay valid, and tmux accepts the result. The restore-path
# round trip through a smaller server lives in test-restore.sh.
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
# many tiny panes: the remainder is taken one row at a time, never below 1 (used to yield -1)
eight='0000,10x132,0,0[10x40,0,0,1,10x40,0,41,2,10x40,0,82,3,10x1,0,123,4,10x1,0,125,5,10x1,0,127,6,10x1,0,129,7,10x1,0,131,8]'
assert_eq "$(layout_scale "$eight" 10 15 | cut -d, -f2-)" "10x15,0,0[10x1,0,0,1,10x1,0,2,2,10x1,0,4,3,10x1,0,6,4,10x1,0,8,5,10x1,0,10,6,10x1,0,12,7,10x1,0,14,8]" "eight panes in 15 rows"
# a box that cannot hold its panes is an error (restore then falls back to tiled)
layout_scale "$eight" 10 10 >/dev/null 2>&1 && fail "unfittable layout accepted"
# garbage is rejected
layout_scale "nope" 10 10 >/dev/null 2>&1 && fail "garbage accepted"

# tmux accepts the scaled string: three panes restored on a 100x30 server from a 190x45 layout
fresh_server l 100 30
T split-window -t l:0 -v; T split-window -t l:0.0 -h
scaled=$(layout_scale "$nested" 100 30)
T select-layout -t l:0 "$scaled" || fail "tmux rejected: $scaled"
assert_eq "$(layout_shape "$(T display -p -t l:0 '#{window_layout}')")" "$(layout_shape "$scaled")" "applied layout"
echo ok

