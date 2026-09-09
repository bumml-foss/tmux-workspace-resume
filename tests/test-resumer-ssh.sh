#!/usr/bin/env bash
# ssh resumer: the exact command line comes back; an ssh that is not the pane's own child is ignored.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

fresh_server net
type_in net:0 "ssh -f /dev/null"          # fake ssh = tail, blocks like a session
T new-window -t net -n indirect
type_in net:1 "sh -c 'ssh -f /dev/null; true'"   # ssh under an intermediate sh: not a direct child
wait_until 5 '[ "$(pane_cmd net:0)" = ssh ]' || fail "fake ssh not running"
wait_until 5 '[ "$(pane_cmd net:1)" = sh ]' || fail "indirect ssh not running"

"$AR" save
snap=$(last_snapshot)
assert_json "$snap" '.sessions[0].windows[0].panes[0].resumer == "ssh"'
assert_json "$snap" '.sessions[0].windows[0].panes[0].restore_cmd == "ssh -f /dev/null"'
assert_json "$snap" '.sessions[0].windows[1].panes[0].restore_cmd == null' "indirect ssh must not be claimed"

kill_server
fresh_server 0
"$AR" restore
wait_until 10 '[ "$(pane_cmd net:0)" = ssh ]' || fail "ssh was not relaunched"
wait_until 5 '[ "$(pane_cmd net:1)" = bash ]' || true
echo ok
