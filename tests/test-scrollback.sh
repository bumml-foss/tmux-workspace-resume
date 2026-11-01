#!/usr/bin/env bash
# scrollback: with SCROLLBACK_LINES a save stores each pane's history beside the snapshot, and a
# restore prints it above the pane's usual shell. A full-screen program's own screen is not kept.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

count() { find "$(snapshot_dir)" -maxdepth 1 -name '2*.json' -type f | wc -l; }
saved() { gzip -dc "${1%.json}.scrollback/$2.gz"; }

fresh_server main 80 24
type_in main:0 'echo marker-$((6 * 7))'
wait_until 5 'has marker-42 T capture-pane -p -t main:0' || fail "marker not printed"
"$AR" -q save
[ ! -e "$(last_snapshot | sed 's/\.json$//').scrollback" ] || fail "scrollback is saved only with SCROLLBACK_LINES"

export TWR_SCROLLBACK_LINES=100
T new-window -t main
type_in main:1 'seq -f hist-%g 40; printf "\033[?1049h\033[H%s-%s" full screen; sleep 60'
wait_until 5 'has full-screen T capture-pane -p -t main:1' || fail "alternate screen not entered"
T new-window -t main
type_in main:2 'printf "\033[?1049h\033[H%s-%s" alt top; sleep 61'
wait_until 5 'has alt-top T capture-pane -p -t main:2' || fail "alternate screen not entered"
"$AR" -q save
snap=$(last_snapshot)
p0=$(jq -r '.sessions[0].windows[0].panes[0].id | ltrimstr("%")' "$snap")
p1=$(jq -r '.sessions[0].windows[1].panes[0].id | ltrimstr("%")' "$snap")
p2=$(jq -r '.sessions[0].windows[2].panes[0].id | ltrimstr("%")' "$snap")
has marker-42 saved "$snap" "$p0" || fail "pane history not saved"
has '^hist-1$' saved "$snap" "$p1" || fail "history before a full-screen program not saved"
has hist-40 saved "$snap" "$p1" || fail "screen under a full-screen program not saved"
has full-screen saved "$snap" "$p1" && fail "a full-screen program's screen must not be saved"
has alt-top saved "$snap" "$p2" && fail "a full-screen program in a pane without history must not be saved"

# an unchanged workspace keeps its snapshot but takes the new scrollback
type_in main:0 'echo later-$((1 + 1))'
wait_until 5 'has later-2 T capture-pane -p -t main:0' || fail "second marker not printed"
"$AR" -q save
assert_eq "$(count)" 2 "unchanged workspace must not write a new snapshot"
has later-2 saved "$snap" "$p0" || fail "unchanged save must refresh the scrollback"

kill_server
fresh_server 0 80 24
"$AR" restore
wait_until 10 'has marker-42 T capture-pane -p -t main:0' || fail "scrollback not printed on restore"
wait_until 10 'has hist-40 T capture-pane -p -S -100 -t main:1' || fail "history under the full-screen program not printed"
has full-screen T capture-pane -p -S -100 -t main:1 && fail "the full-screen program's screen was printed"
wait_until 10 '[ "$(pane_cmd main:0)" = bash ]' || fail "restored pane does not run the shell: $(pane_cmd main:0)"
# tmux with an empty default-command starts a login shell; so must the restored pane
assert_eq "$(ps -o args= -p "$(T display -p -t main:0 '#{pane_pid}')")" "-bash" "login shell"
type_in main:0 'echo typed-$((2 + 3))'
wait_until 5 'has typed-5 T capture-pane -p -t main:0' || fail "restored shell does not take input"
# with a default-command (byobu sets one) the restored pane runs it
T kill-window -t main:1
T set -g default-command 'exec bash --noprofile'
"$AR" -q restore
wait_until 10 'has hist-40 T capture-pane -p -S -100 -t main:1' || fail "scrollback not printed with a default-command"
assert_eq "$(ps -o args= -p "$(T display -p -t main:1 '#{pane_pid}')")" "bash --noprofile" "default-command"

# pruned snapshots take their scrollback with them
TWR_KEEP_SNAPSHOTS=1 "$AR" -q save --force
assert_eq "$(find "$(snapshot_dir)" -maxdepth 1 -name '*.scrollback' | wc -l)" 1 "scrollback of pruned snapshots"
echo ok
