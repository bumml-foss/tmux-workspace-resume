# shellcheck shell=bash
# tmux-workspace-resume — snapshot files: $XDG_STATE_HOME/tmux-workspace-resume/snapshots/<timestamp>.json, with
# last.json pointing at the newest one and <timestamp>.scrollback/ beside a snapshot saved with
# SCROLLBACK_LINES. Old snapshots are pruned to KEEP_SNAPSHOTS.
# SPDX-License-Identifier: GPL-3.0-or-later

snapshot_dir() { printf '%s' "$(state_dir)/snapshots"; }

# snapshot_stamp: YYYYmmddTHHMMSS.mmm from a single clock reading. Not date(1): the Rust
# coreutils date (Ubuntu 26.04) can pair the milliseconds with the previous second, so
# consecutive names would not sort by age.
snapshot_stamp() {
	local t=$EPOCHREALTIME frac
	frac=${t#*[.,]}
	printf '%(%Y%m%dT%H%M%S)T.%s' "${t%[.,]*}" "${frac:0:3}"
}

# snapshot_write [SCROLLBACK_DIR]: JSON on stdin -> validated file on disk; prints the path.
# Names carry milliseconds so they are unique and sort by age; the directory lock serialises
# concurrent savers (timer, hook, key binding, settle save). SCROLLBACK_DIR (from
# save_scrollback) moves in beside it.
snapshot_write() {
	local dir final tmp scrollback=${1:-}
	dir=$(snapshot_dir)
	mkdir -p "$dir"
	exec 7>"$dir/.lock"
	flock 7
	final=$dir/$(snapshot_stamp).json
	while [ -e "$final" ]; do sleep 0.01; final=$dir/$(snapshot_stamp).json; done
	tmp=$(mktemp "$dir/.tmp.XXXXXX")
	if ! jq -e . > "$tmp"; then
		rm -f "$tmp"
		[ -z "$scrollback" ] || rm -rf "$scrollback"
		flock -u 7
		die "refusing to write an invalid snapshot"
	fi
	mv "$tmp" "$final"
	[ -z "$scrollback" ] || mv "$scrollback" "${final%.json}.scrollback"
	ln -sfn "$(basename "$final")" "$dir/last.json"
	snapshot_prune
	flock -u 7
	printf '%s' "$final"
}

# snapshot_refresh [SCROLLBACK_DIR]: the workspace is unchanged; mark the newest snapshot as
# current and replace its scrollback with SCROLLBACK_DIR.
snapshot_refresh() {
	local dir last
	dir=$(snapshot_dir)
	exec 7>"$dir/.lock"
	flock 7
	last=$(readlink -f "$dir/last.json")
	touch "$last"
	if [ -n "${1:-}" ]; then
		rm -rf "${last%.json}.scrollback"
		mv "$1" "${last%.json}.scrollback"
	fi
	flock -u 7
}

# snapshot_prune: also removes the scrollback of pruned snapshots and the leftovers of a save
# that was killed while capturing.
snapshot_prune() {
	local dir keep
	dir=$(snapshot_dir)
	find "$dir" -maxdepth 1 -name '.tmp.*' -mmin +60 -exec rm -rf {} + 2>/dev/null || true
	keep=${KEEP_SNAPSHOTS:-20}
	[ "$keep" -gt 0 ] 2>/dev/null || return 0
	find "$dir" -maxdepth 1 -name '*.json' -type f | sort | head -n "-$keep" | while IFS= read -r f; do
		rm -f "$f"
		rm -rf "${f%.json}.scrollback"
	done
}

# snapshot_resolve [NAME]: "" or "last" -> newest; a path -> itself; a timestamp -> that file.
snapshot_resolve() {
	local arg=${1:-last} dir f
	dir=$(snapshot_dir)
	case $arg in
		last|"") f=$dir/last.json ;;
		*/*|*.json) f=$arg ;;
		*) f=$dir/$arg.json ;;
	esac
	[ -e "$f" ] || { log_error "no snapshot found ($f)"; return 1; }
	readlink -f "$f"
}

# snapshot_summary FILE: "1 session, 8 windows, 13 panes, 10 commands (claude 9, ssh 1)"
snapshot_summary() {
	jq -r '
		[.sessions[].windows[].panes[]] as $p
		| ($p | map(select(.restore_cmd != null and .restore_cmd != "")) | group_by(.resumer)
		   | map("\(.[0].resumer) \(length)") | join(", ")) as $by
		| "\(.sessions | length) session(s), \([.sessions[].windows[]] | length) window(s), \($p | length) pane(s), "
		  + "\($p | map(select(.restore_cmd != null and .restore_cmd != "")) | length) command(s)"
		  + (if $by == "" then "" else " (" + $by + ")" end)' "$1"
}

cmd_list() {
	local dir last f ts summary boot mark
	dir=$(snapshot_dir)
	[ -d "$dir" ] || { echo "no snapshots yet ($dir)"; return 0; }
	last=$(readlink -f "$dir/last.json" 2>/dev/null || true)
	find "$dir" -maxdepth 1 -name '*.json' -type f | sort -r | while IFS= read -r f; do
		ts=$(basename "$f" .json)
		summary=$(snapshot_summary "$f" 2>/dev/null || echo "unreadable")
		boot=$(jq -r '.boot_id // "?"' "$f" 2>/dev/null | cut -c1-8)
		mark=""; [ "$f" = "$last" ] && mark="  (last)"
		printf '%s  boot %s  %s%s\n' "$ts" "$boot" "$summary" "$mark"
	done
}
