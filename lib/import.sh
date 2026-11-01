# shellcheck shell=bash
# tmux-workspace-resume — import a tmux-resurrect save file as a snapshot.
# SPDX-License-Identifier: GPL-3.0-or-later

# import_resurrect_json FILE: the snapshot document for a tmux-resurrect save file. Its lines are
# tab-separated (empty fields kept, so split in jq, never with `read`):
#   pane     session window_index window_active :window_flags pane_index pane_title :dir pane_active pane_command :full_command
#   window   session window_index :window_name window_active :window_flags window_layout automatic_rename
#   grouped_session  name original_session :alternate_window :active_window
#   state    client_session client_last_session
# Grouped sessions are clones (byobu attaches through them) and are left out, like on a save. A
# pane's program comes back when its name is in RESUME_COMMANDS (or is ssh), as tmux-resurrect's
# own restore would do; agents come back as shells, the file has no session ids.
import_resurrect_json() {
	local allowed
	read -ra allowed <<< "${RESUME_COMMANDS:-} ssh"
	jq -R -s --arg saved_at "$(date -Is -r "$1")" --arg host "$(hostname)" \
		--argjson allowed "$(printf '%s\n' "${allowed[@]}" | jq -R . | jq -s .)" '
		split("\n") | map(select(length > 0) | split("\t")) as $rows
		| ($rows | map(select(.[0] == "grouped_session") | .[1])) as $clones
		| ($rows | map(select((.[0] == "pane" or .[0] == "window") and (.[1] as $s | $clones | index([$s]) | not)))) as $own
		| if ($own | map(select(.[0] == "pane")) | length) == 0 then error("no panes in this file") else . end
		| if ($own | any((.[0] == "pane" and length != 11) or (.[0] == "window" and length != 8)))
		  then error("not a tmux-resurrect save file this version can read") else . end
		| ($own | map(select(.[0] == "pane")) | to_entries | map(.value + ["%\(.key)"])) as $panes
		| ($own | map(select(.[0] == "window"))) as $windows
		| ($windows | reduce .[] as $w ([]; if index([$w[1]]) then . else . + [$w[1]] end)) as $names
		| {version: 1, saved_at: $saved_at, boot_id: "tmux-resurrect", tmux_version: "", hostname: $host,
		   sessions: [$names[] as $s | {name: $s, group: $s, saved_from: $s,
			windows: [$windows[] | select(.[1] == $s) | . as $w
				| ($w[6] | capture("^[0-9a-f]+,(?<w>[0-9]+)x(?<h>[0-9]+)") // {w: "0", h: "0"}) as $size
				| {index: ($w[2] | tonumber), id: "@\($w[2])", name: $w[3][1:], automatic_rename: ($w[7] != "off"),
				   layout: $w[6], active: ($w[4] == "1"), width: ($size.w | tonumber), height: ($size.h | tonumber),
				   panes: [$panes[] | select(.[1] == $s and .[2] == $w[2]) | (.[7][1:] | gsub("\\\\ "; " ")) as $cwd
					| (.[10][1:]) as $full | (.[9] as $c | $allowed | index([$c])) as $listed
					| {index: (.[5] | tonumber), id: .[11], pid: 0, cwd: $cwd, command: .[9], active: (.[8] == "1"),
					   title: .[6], resumer: (if $listed and $full != "" then "resurrect" else null end),
					   restore_cmd: (if $listed and $full != "" then $full else null end), restore_cwd: $cwd, meta: {}}]}]}
			| . + {active_window: ((.windows | map(select(.active)) | .[0].index) // .windows[0].index)}]}' "$1"
}

# import_resurrect_contents JSON ARCHIVE: tmux-resurrect's pane_contents.tar.gz (one file per
# pane, named pane-<session>:<window>.<pane>) as a scrollback directory for the snapshot.
import_resurrect_contents() {
	local json=$1 archive=$2 dir tmp id key text
	tmp=$(mktemp -d)
	if ! tar xzf "$archive" -C "$tmp" ./pane_contents 2>/dev/null; then rm -rf "$tmp"; return 0; fi
	mkdir -p "$(snapshot_dir)"
	dir=$(mktemp -d "$(snapshot_dir)/.tmp.XXXXXX")
	while IFS=$'\t' read -r id key; do
		[ -f "$tmp/pane_contents/pane-$key" ] || continue
		text=$(cat "$tmp/pane_contents/pane-$key")
		[ -n "$text" ] || continue
		printf '%s\n\033[0m' "$text" | gzip > "$dir/${id#%}.gz"
	done < <(printf '%s' "$json" | jq -r '.sessions[] as $s | $s.windows[] as $w | $w.panes[] | "\(.id)\t\($s.name):\($w.index).\(.index)"')
	rm -rf "$tmp"
	printf '%s' "$dir"
}

# cmd_import [FILE]: default is tmux-resurrect's newest save. Its pane contents (saved with
# @resurrect-capture-pane-contents) belong to the newest save only, so they come along with it.
cmd_import() {
	local file=${1:-} d json scrollback="" snap
	[ $# -le 1 ] || die "usage: tmux-workspace-resume import [tmux-resurrect file]"
	if [ -z "$file" ]; then
		for d in "${XDG_DATA_HOME:-$HOME/.local/share}/tmux/resurrect" "$HOME/.tmux/resurrect"; do
			if [ -e "$d/last" ]; then file=$d/last; break; fi
		done
		[ -n "$file" ] || die "no tmux-resurrect save found (~/.local/share/tmux/resurrect/last or ~/.tmux/resurrect/last); pass the file"
	fi
	[ -r "$file" ] || die "cannot read $file"
	json=$(import_resurrect_json "$file") || die "cannot import $file"
	d=$(dirname "$(readlink -f "$file")")
	if [ "$(readlink -f "$file")" = "$(readlink -f "$d/last" 2>/dev/null)" ] && [ -f "$d/pane_contents.tar.gz" ]; then
		scrollback=$(import_resurrect_contents "$json" "$d/pane_contents.tar.gz")
	fi
	snap=$(printf '%s' "$json" | snapshot_write "$scrollback") || return 1
	log_info "imported $file: $(snapshot_summary "$snap") -> $snap"
	printf 'restore it with: tmux-workspace-resume restore %s\n' "$(basename "$snap" .json)"
}
