#!/usr/bin/env bash
# byobu attaches through grouped clone sessions: only one session per group is saved, named after the group.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

fresh_server main
T new-window -t main -n second
T new-session -d -t main -s clone-1
T new-session -d -t main -s clone-2
assert_eq "$(T list-sessions -F x | wc -l)" 3 "three sessions in the group"
"$AR" save
snap=$(last_snapshot)
assert_json "$snap" '.sessions | length == 1'
assert_json "$snap" '.sessions[0].name == "main" and .sessions[0].group == "main"'
assert_json "$snap" '.sessions[0].windows | length == 2'
echo ok
