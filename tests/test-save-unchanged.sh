#!/usr/bin/env bash
# save: an unchanged workspace writes no new snapshot, only refreshes the newest one's mtime;
# --force and a real change still write.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

count() { find "$(snapshot_dir)" -maxdepth 1 -name '2*.json' -type f | wc -l; }

fresh_server main
"$AR" -q save
first=$(last_snapshot)
m0=$(stat -c %Y "$first")
sleep 1.1
"$AR" -q save
assert_eq "$(count)" 1 "unchanged workspace must not write a new snapshot"
assert_eq "$(last_snapshot)" "$first" "last.json must stay on the existing snapshot"
[ "$(stat -c %Y "$first")" -gt "$m0" ] || fail "unchanged save must refresh the snapshot's mtime"

T select-pane -t main:0 -T "an agent rewriting its title"
"$AR" -q save
assert_eq "$(count)" 1 "a pane title change is not a workspace change"

"$AR" -q save --force
assert_eq "$(count)" 2 "--force writes even when unchanged"

T new-window -t main -n added
"$AR" -q save
assert_eq "$(count)" 3 "a changed workspace writes a new snapshot"
assert_json "$(last_snapshot)" '.sessions[0].windows | length == 2'

T rename-window -t main:0 renamed
"$AR" -q save
assert_eq "$(count)" 4 "a manual window name is restored, so renaming is a change"
echo ok
