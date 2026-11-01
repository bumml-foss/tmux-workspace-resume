#!/usr/bin/env bash
# whitelist resumer: programs in RESUME_COMMANDS come back with their arguments, others do not.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

export TWR_RESUME_COMMANDS="tail"
fresh_server w
type_in w:0 "tail -f /dev/null"
T new-window -t w
type_in w:1 "sleep 1000"
wait_until 5 '[ "$(pane_cmd w:0)" = tail ]' || fail "tail not running"
wait_until 5 '[ "$(pane_cmd w:1)" = sleep ]' || fail "sleep not running"
"$AR" save
snap=$(last_snapshot)
assert_json "$snap" '.sessions[0].windows[0].panes[0].resumer == "whitelist"'
assert_json "$snap" '.sessions[0].windows[0].panes[0].restore_cmd == "tail -f /dev/null"'
assert_json "$snap" '.sessions[0].windows[1].panes[0].restore_cmd == null' "sleep is not whitelisted"

# The foreground job: pipelines, nested shells, sudo, serial devices; a suspended job as fallback.
export TWR_RESUME_COMMANDS="tail grep fake-dmesg"
# a `sudo` that keeps running as "sudo <command>" like the real one: bash searches PATH for the script
ln -s "$(command -v bash)" "$TMP/bin/sudo"
printf '#!/usr/bin/env bash\nsleep 1000; :\n' > "$TMP/bin/fake-dmesg"
chmod +x "$TMP/bin/fake-dmesg"
mkdir -p "$TMP/dev" "$TMP/by-id"
touch "$TMP/dev/ttyUSB3"
ln -s ../dev/ttyUSB3 "$TMP/by-id/usb-FAKE-if00-port0"
export TWR_SERIAL_BY_ID=$TMP/by-id
job() {
	T new-window -t w
	type_in "w:$1" "$2"
	wait_until 5 "[ \"\$(pane_cmd w:$1)\" = $3 ]" || fail "window $1: $2 not running"
}
job 2 "tail -f /dev/null | grep -v x" tail
job 3 "tail -f /dev/null | cat" tail
job 4 "tail -f /dev/null > $TMP/out.txt" tail
job 5 "bash --norc" bash
type_in w:5 "tail -f /dev/null"
wait_until 5 '[ "$(pane_cmd w:5)" = tail ]' || fail "nested tail not running"
job 6 "sudo fake-dmesg -w --color=always" sudo
job 7 "tail -f $TMP/dev/ttyUSB3" tail
job 8 "tail -f /dev/null" tail
T send-keys -t w:8 C-z
wait_until 5 '[ "$(pane_cmd w:8)" = bash ]' || fail "tail not suspended"
"$AR" save
snap=$(last_snapshot)
cmd_of() { jq -r ".sessions[0].windows[] | select(.index == $1) | .panes[0].restore_cmd" "$snap"; }
assert_eq "$(cmd_of 2)" "tail -f /dev/null | grep -v x" "pipeline of listed programs"
assert_eq "$(cmd_of 3)" null "a pipeline with an unlisted program"
assert_eq "$(cmd_of 4)" null "a redirected job"
assert_eq "$(cmd_of 5)" "tail -f /dev/null" "job of a nested shell"
assert_eq "$(cmd_of 6)" "sudo fake-dmesg -w --color=always" "sudo counts as its command"
assert_eq "$(cmd_of 7)" "tail -f $TMP/by-id/usb-FAKE-if00-port0" "serial device by id"
assert_eq "$(cmd_of 8)" "tail -f /dev/null" "suspended job"

# a resumer that emits junk is ignored, a user override wins over the shipped one
mkdir -p "$XDG_CONFIG_HOME/tmux-workspace-resume/resumers"
cat > "$XDG_CONFIG_HOME/tmux-workspace-resume/resumers/05-junk" <<'JUNK'
#!/usr/bin/env bash
[ "$1" = info ] && { echo junk; exit 0; }
echo "this is not json"
exit 0
JUNK
cat > "$XDG_CONFIG_HOME/tmux-workspace-resume/resumers/90-whitelist" <<'OVR'
#!/usr/bin/env bash
[ "$1" = info ] && { echo override; exit 0; }
[ "$TWR_COMMAND" = sleep ] && { echo '{"cmd":"echo overridden","meta":{}}'; exit 0; }
exit 1
OVR
chmod +x "$XDG_CONFIG_HOME/tmux-workspace-resume/resumers/"*
listing=$("$AR" resumers)
echo "$listing" | grep -q "05-junk" || fail "user resumer not listed: $listing"
assert_eq "$(echo "$listing" | grep -c '90-whitelist')" 1 "override replaces the shipped resumer"
"$AR" save --force
snap=$(last_snapshot)
assert_json "$snap" '.sessions[0].windows[1].panes[0].restore_cmd == "echo overridden"'
assert_json "$snap" '.sessions[0].windows[0].panes[0].restore_cmd == null' "override no longer claims tail"
echo ok
