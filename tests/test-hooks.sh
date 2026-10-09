#!/usr/bin/env bash
# tmux-workspace-resume.tmux installs hooks at index 900 and key bindings; a new window triggers a debounced save;
# hook remove cleans up.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

export TWR_SAVE_DEBOUNCE_S=1
export TWR_AUTO_RESTORE=never
fresh_server h
T run-shell "$REPO/tmux-workspace-resume.tmux"
hooks=$(T show-hooks -g)
echo "$hooks" | grep -q 'after-new-window\[900\].*save --debounce' || fail "after-new-window hook missing: $hooks"
assert_eq "$(echo "$hooks" | grep -c '\[900\]')" 10 "ten hooks installed"
has 'C-s .*run-shell.*save' T list-keys || fail "save key binding missing"
has 'C-r .*run-shell.*restore' T list-keys || fail "restore key binding missing"

T new-window -t h -n triggered
wait_until 6 '[ -e "$(snapshot_dir)/last.json" ]' || fail "no snapshot after new-window (hook + debounce)"
assert_json "$(last_snapshot)" '.sessions[0].windows | length == 2'

# a burst of events yields one snapshot (debounce), not one per event
before=$(find "$(snapshot_dir)" -name '*.json' -type f | wc -l)
for i in 1 2 3 4 5; do T new-window -t h -n "burst$i"; done
sleep 3
after=$(find "$(snapshot_dir)" -name '*.json' -type f | wc -l)
[ $((after - before)) -le 2 ] || fail "debounce: $((after - before)) snapshots for 5 events"
assert_json "$(last_snapshot)" '.sessions[0].windows | length == 7'

"$AR" hook remove
assert_eq "$(T show-hooks -g | grep -c '\[900\]')" 0 "hooks removed"
has 'C-s .*tmux-workspace-resume' T list-keys && fail "save key still bound"
echo ok
