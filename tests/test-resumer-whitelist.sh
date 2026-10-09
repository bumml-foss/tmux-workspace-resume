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
