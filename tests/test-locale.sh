#!/usr/bin/env bash
# locale: save and restore work without a UTF-8 locale. A non-UTF-8 tmux client gets the tabs in
# format output replaced with "_" unless it is started with -u.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

export LC_ALL=C LANG=C
unset LC_CTYPE
mkdir -p "$HOME/proj"
fresh_server work
T new-window -t work -n logs -c "$HOME/proj"
T split-window -t work:1 -v -c "$HOME"
"$AR" save
assert_json "$(last_snapshot)" '.sessions[0].name == "work" and (.sessions[0].windows | length) == 2' "snapshot under LC_ALL=C"
assert_json "$(last_snapshot)" '.sessions[0].windows[1].name == "logs" and (.sessions[0].windows[1].panes | length) == 2'
kill_server

fresh_server 0
"$AR" restore
assert_eq "$(T list-panes -s -t work -F x | wc -l)" 3 "panes restored under LC_ALL=C"
assert_eq "$(T display -p -t work:1 '#{window_name}')" logs "window name"
echo ok
