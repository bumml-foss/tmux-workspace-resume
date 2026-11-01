#!/usr/bin/env bash
# import: a tmux-resurrect save file (and its pane contents) becomes a snapshot that restores the
# sessions, windows, panes, titles, cwds, layouts and whitelisted programs.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

mkdir -p "$HOME/proj a" "$HOME/src"
fresh_server work 160 40
T rename-window -t work:0 edit
T select-pane -t work:0.0 -T "notes pane"
T new-window -t work -c "$HOME/proj a"
T split-window -t work:1 -h -c "$HOME/src"
type_in work:1.1 'tail -f /dev/null'
T new-window -t work -n logs -c "$HOME"
T set -w -t work:2 automatic-rename off
type_in work:2 'echo hello-$((40 + 2))'
T new-session -d -s misc -c "$HOME/src"
T new-session -d -s work-2 -t work
T select-window -t work:1
wait_until 5 '[ "$(pane_cmd work:1.1)" = tail ]' || fail "tail not running"
wait_until 5 'has hello-42 T capture-pane -p -t work:2' || fail "marker not printed"
before=$(T list-panes -s -t work -F '#{window_index}:#{?automatic-rename,auto,#{window_name}}:#{pane_index}:#{pane_current_path}')
layout_before=$(T display -p -t work:1 '#{window_layout}')

# What tmux-resurrect's save.sh writes, from its own format strings: the panes and windows of
# every session but the grouped clones, ":"-prefixed fields, the first space of a directory
# escaped, the full command from its default "ps" strategy (the pane shell's child).
R=$HOME/.local/share/tmux/resurrect
mkdir -p "$R/save/pane_contents"
file=$R/tmux_resurrect_20261101T120000.txt
US=$'\x1f'
{
	printf 'grouped_session\twork-2\twork\t:\t:1\n'
	T list-panes -a -F "#{session_name}${US}#{window_index}${US}#{window_active}${US}#{window_flags}${US}#{pane_index}${US}#{pane_title}${US}#{pane_current_path}${US}#{pane_active}${US}#{pane_current_command}${US}#{pane_pid}" |
		while IFS=$US read -r s w wa wf p title dir pa cmd pid; do
			[ "$s" != work-2 ] || continue
			full=$(ps -o args= --ppid "$pid" | head -n1) || true
			printf 'pane\t%s\t%s\t%s\t:%s\t%s\t%s\t:%s\t%s\t%s\t:%s\n' "$s" "$w" "$wa" "$wf" "$p" "$title" "${dir/ /\\ }" "$pa" "$cmd" "$full"
			T capture-pane -epJ -t "$s:$w.$p" > "$R/save/pane_contents/pane-$s:$w.$p"
		done
	T list-windows -a -F "#{session_name}${US}#{window_index}${US}#{window_name}${US}#{window_active}${US}#{window_flags}${US}#{window_layout}" |
		while IFS=$US read -r s w name wa wf layout; do
			[ "$s" != work-2 ] || continue
			auto=$(T show-window-options -vt "$s:$w" automatic-rename)
			printf 'window\t%s\t%s\t:%s\t%s\t:%s\t%s\t%s\n' "$s" "$w" "$name" "$wa" "$wf" "$layout" "${auto:-:}"
		done
	printf 'state\twork\tmisc\n'
} > "$file"
tar cf - -C "$R/save" ./pane_contents/ | gzip > "$R/pane_contents.tar.gz"
ln -s "$(basename "$file")" "$R/last"
kill_server

fresh_server 0 160 40
out=$("$AR" -q import)
stamp=$(printf '%s' "$out" | sed -n 's/^restore it with: tmux-workspace-resume restore //p')
[ -n "$stamp" ] || fail "import printed no snapshot: $out"
"$AR" -q restore "$stamp"
assert_eq "$(T list-sessions -F '#{session_name}' | sort | tr '\n' ' ')" "misc work " "sessions without the grouped clone"
assert_eq "$(layout_shape "$(T display -p -t work:1 '#{window_layout}')")" "$(layout_shape "$layout_before")" "layout shape"
assert_eq "$(T display -p -t work '#{window_index}')" 1 "active window"
assert_eq "$(T display -p -t work:2 '#{automatic-rename}')" 0 "automatic-rename off"
assert_eq "$(T display -p -t work:0.0 '#{pane_title}')" "notes pane" "pane title"
wait_until 10 '[ "$(pane_cmd work:1.1)" = tail ]' || fail "whitelisted program not relaunched: $(pane_cmd work:1.1)"
assert_eq "$(T list-panes -s -t work -F '#{window_index}:#{?automatic-rename,auto,#{window_name}}:#{pane_index}:#{pane_current_path}')" "$before" "windows/panes/cwds"
wait_until 10 'has hello-42 T capture-pane -p -t work:2' || fail "pane contents not printed"

printf 'not\ta resurrect file\n' > "$TMP/junk"
"$AR" -q import "$TMP/junk" 2>/dev/null && fail "a file in another format must be refused"
echo ok
