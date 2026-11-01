#!/usr/bin/env bash
# save --timer: TIMER_SAVE=always saves; after-input saves only when an attached client had
# activity after the newest snapshot, or when there is no snapshot yet.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

count() { find "$(snapshot_dir)" -maxdepth 1 -name '2*.json' -type f | wc -l; }

fresh_server main
TWR_TIMER_SAVE=after-input "$AR" -q save --timer
assert_eq "$(count)" 1 "after-input saves when there is no snapshot yet"

sleep 1.1
T new-window -t main -n w1
TWR_TIMER_SAVE=after-input "$AR" -q save --timer
assert_eq "$(count)" 1 "after-input skips without client activity"
"$AR" -q save --timer
assert_eq "$(count)" 2 "TIMER_SAVE=always saves on the timer"
"$AR" -q save
assert_eq "$(count)" 2 "hook and manual saves are not gated"

# A control-mode client counts its attach time as activity (its commands do not; keystrokes of
# a terminal client do).
sleep 1.1
mkfifo "$TMP/ctl"
T -C attach -t main < "$TMP/ctl" > /dev/null 2>&1 &
exec 3> "$TMP/ctl"
wait_until 5 '[ -n "$(T list-clients -F x)" ]' || fail "control client did not attach"
T new-window -t main -n w2
TWR_TIMER_SAVE=after-input "$AR" -q save --timer
assert_eq "$(count)" 3 "after-input saves after client activity"
exec 3>&-
echo ok
