#!/usr/bin/env bash
# restore --auto: runs once per server (marker), honours AUTO_RESTORE=reboot|never and AI_REVIVE_NO_RESTORE,
# and refuses to overwrite a rich snapshot with the blank one of a freshly started server.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

fresh_server main
T new-window -t main -n two
T new-window -t main -n three
"$AR" save
kill_server

# AUTO_RESTORE=reboot (default): the snapshot is from this boot -> nothing happens, marker written
fresh_server 0
"$AR" restore --auto
assert_eq "$(T list-windows -t 0 -F x | wc -l)" 1 "reboot policy must not restore within the same boot"
[ -e "$XDG_RUNTIME_DIR/ai-revive/restored-$(T display -p '#{pid}')" ] || fail "marker missing"

# a snapshot from "another boot" -> restored; second --auto is a no-op thanks to the marker
rm -f "$XDG_RUNTIME_DIR"/ai-revive/restored-*
jq '.boot_id = "00000000-0000-0000-0000-000000000000"' "$(last_snapshot)" > "$(snapshot_dir)/old.json"
"$AR" restore --auto old
T has-session -t main || fail "not restored from an old-boot snapshot"
assert_eq "$(T list-windows -t main -F x | wc -l)" 3 "three windows restored"
T new-window -t main -n extra
"$AR" restore --auto old
assert_eq "$(T list-windows -t main -F x | wc -l)" 4 "second --auto must not touch the server"

# AUTO_RESTORE=always restores even from this boot; never/AI_REVIVE_NO_RESTORE do nothing
kill_server; rm -f "$XDG_RUNTIME_DIR"/ai-revive/restored-*
fresh_server 0
AI_REVIVE_AUTO_RESTORE=always "$AR" restore --auto
assert_eq "$(T list-windows -t main -F x | wc -l)" 3 "always policy"
kill_server; rm -f "$XDG_RUNTIME_DIR"/ai-revive/restored-*
fresh_server 0
AI_REVIVE_AUTO_RESTORE=always AI_REVIVE_NO_RESTORE=1 "$AR" restore --auto
AI_REVIVE_AUTO_RESTORE=never "$AR" restore --auto
assert_eq "$(T list-sessions -F x | wc -l)" 1 "never / NO_RESTORE"

# blank-server guard: a plain save on the fresh server keeps the rich snapshot; --force overwrites
"$AR" save
assert_json "$(last_snapshot)" '.sessions[0].windows | length == 3'
"$AR" save --force
assert_json "$(last_snapshot)" '.sessions[0].windows | length == 1'

# restoring marker: a save during a restore is skipped
echo $$ > "$XDG_RUNTIME_DIR/ai-revive/restoring"
T new-window -t 0:
"$AR" save
assert_json "$(last_snapshot)" '.sessions[0].windows | length == 1' "save must skip while restoring"
rm -f "$XDG_RUNTIME_DIR/ai-revive/restoring"
echo ok
