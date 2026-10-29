#!/usr/bin/env bash
# restore --auto: runs once per server (marker), honours AUTO_RESTORE=reboot|never and TWR_NO_RESTORE,
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
ls "$XDG_RUNTIME_DIR"/tmux-workspace-resume/restored-*-"$(T display -p '#{pid}')" >/dev/null 2>&1 || fail "marker missing"

# a snapshot from "another boot" -> restored; second --auto is a no-op thanks to the marker
rm -f "$XDG_RUNTIME_DIR"/tmux-workspace-resume/restored-* "$XDG_RUNTIME_DIR"/tmux-workspace-resume/attempted-*
jq '.boot_id = "00000000-0000-0000-0000-000000000000"' "$(last_snapshot)" > "$(snapshot_dir)/old.json"
"$AR" restore --auto old
T has-session -t main || fail "not restored from an old-boot snapshot"
assert_eq "$(T list-windows -t main -F x | wc -l)" 3 "three windows restored"
T new-window -t main -n extra
"$AR" restore --auto old
assert_eq "$(T list-windows -t main -F x | wc -l)" 4 "second --auto must not touch the server"

# AUTO_RESTORE=always restores even from this boot; never/TWR_NO_RESTORE do nothing
kill_server; rm -f "$XDG_RUNTIME_DIR"/tmux-workspace-resume/restored-* "$XDG_RUNTIME_DIR"/tmux-workspace-resume/attempted-*
fresh_server 0
TWR_AUTO_RESTORE=always "$AR" restore --auto
assert_eq "$(T list-windows -t main -F x | wc -l)" 3 "always policy"
kill_server; rm -f "$XDG_RUNTIME_DIR"/tmux-workspace-resume/restored-* "$XDG_RUNTIME_DIR"/tmux-workspace-resume/attempted-*
fresh_server 0
TWR_AUTO_RESTORE=always TWR_NO_RESTORE=1 "$AR" restore --auto
TWR_AUTO_RESTORE=never "$AR" restore --auto
assert_eq "$(T list-sessions -F x | wc -l)" 1 "never / NO_RESTORE"

# previous-boot guard: while the newest snapshot is from another boot and no restore ran on this
# server, plain saves keep it; --force overwrites; after a restore saves flow again
jq '.boot_id = "00000000-0000-0000-0000-000000000000"' "$(last_snapshot)" > "$(snapshot_dir)/older.json"
ln -sfn older.json "$(snapshot_dir)/last.json"
rm -f "$XDG_RUNTIME_DIR"/tmux-workspace-resume/restored-* "$XDG_RUNTIME_DIR"/tmux-workspace-resume/attempted-*
"$AR" save
assert_eq "$(basename "$(last_snapshot)")" "older.json" "save must keep a previous-boot snapshot until a restore ran"
"$AR" restore --auto                       # AUTO_RESTORE=reboot -> restores the 3 windows, writes the marker
assert_eq "$(T list-windows -t main -F x | wc -l)" 3 "restored"
"$AR" save
[ "$(basename "$(last_snapshot)")" != "older.json" ] || fail "save must proceed once a restore ran"
assert_json "$(last_snapshot)" '.sessions[0].windows | length == 3'
# a user who deliberately shrinks the workspace gets that saved (no shape heuristics)
T kill-window -t main:1; T kill-window -t main:2
"$AR" save
assert_json "$(last_snapshot)" '.sessions[0].windows | length == 1' "shrunk workspace saved"
# --force always writes
jq '.boot_id = "00000000-0000-0000-0000-000000000000"' "$(last_snapshot)" > "$(snapshot_dir)/older2.json"
ln -sfn older2.json "$(snapshot_dir)/last.json"; rm -f "$XDG_RUNTIME_DIR"/tmux-workspace-resume/restored-* "$XDG_RUNTIME_DIR"/tmux-workspace-resume/attempted-*
"$AR" save --force
[ "$(basename "$(last_snapshot)")" != "older2.json" ] || fail "--force must write"

# AUTO_RESTORE=never and TWR_NO_RESTORE must not hold saves for the whole boot
jq '.boot_id = "00000000-0000-0000-0000-000000000000"' "$(last_snapshot)" > "$(snapshot_dir)/older3.json"
ln -sfn older3.json "$(snapshot_dir)/last.json"; rm -f "$XDG_RUNTIME_DIR"/tmux-workspace-resume/restored-* "$XDG_RUNTIME_DIR"/tmux-workspace-resume/attempted-*
TWR_AUTO_RESTORE=never "$AR" save
[ "$(basename "$(last_snapshot)")" != "older3.json" ] || fail "AUTO_RESTORE=never must not hold saves"
ln -sfn older3.json "$(snapshot_dir)/last.json"; rm -f "$XDG_RUNTIME_DIR"/tmux-workspace-resume/restored-* "$XDG_RUNTIME_DIR"/tmux-workspace-resume/attempted-*
TWR_NO_RESTORE=1 "$AR" restore --auto
"$AR" save
[ "$(basename "$(last_snapshot)")" != "older3.json" ] || fail "a decision not to restore must let saves proceed"

# two saves in quick succession get distinct, correctly ordered files
"$AR" save --force; "$AR" save --force
n=$(find "$(snapshot_dir)" -maxdepth 1 -name '*.json' -type f | wc -l)
[ "$n" -ge 2 ] || fail "concurrent-safe naming"
[ "$(basename "$(last_snapshot)")" = "$(find "$(snapshot_dir)" -maxdepth 1 -name '2*.json' -type f -printf '%f\n' | sort | tail -1)" ] || fail "last.json must be the newest by name"

# restore lock: a save while a restore holds the lock is skipped; a dead restore leaves no trace
exec 8>"$XDG_RUNTIME_DIR/tmux-workspace-resume/restore.lock"; flock 8
T new-window -t main:
"$AR" save
assert_json "$(last_snapshot)" '.sessions[0].windows | length == 1' "save must skip while a restore holds the lock"
flock -u 8; exec 8>&-
"$AR" save
assert_json "$(last_snapshot)" '.sessions[0].windows | length == 2' "save proceeds once the lock is gone"
echo ok
