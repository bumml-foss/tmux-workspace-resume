# shellcheck shell=bash
# tmux-workspace-resume — snapshot the running tmux server.
# SPDX-License-Identifier: GPL-3.0-or-later

# save_pick_sessions: one representative per session group (byobu attaches every client through
# a grouped clone; all clones share the windows). Prints "name<US>group" lines.
save_pick_sessions() {
	local US=$'\x1f' name group attached created key score
	local -A best=() best_score=() best_created=()
	while IFS=$US read -r name group attached created; do
		[ -n "$name" ] || continue
		key=${group:-$name}
		score=0
		[ "${attached:-0}" -gt 0 ] && score=$((score + 2))
		[ "$name" = "$key" ] && score=$((score + 1))
		if [ -z "${best[$key]+x}" ] || [ "$score" -gt "${best_score[$key]}" ] ||
			{ [ "$score" -eq "${best_score[$key]}" ] && [ "${created:-0}" -lt "${best_created[$key]}" ]; }; then
			best[$key]=$name; best_score[$key]=$score; best_created[$key]=${created:-0}
		fi
	done < <(tmux_cmd list-sessions -F "#{session_name}	#{session_group}	#{session_attached}	#{session_created}" | tr '\t' '\037')
	for key in "${!best[@]}"; do printf '%s%s%s\n' "${best[$key]}" "$US" "$key"; done | sort
}

# save_collect_session NAME GROUP: JSON object for one session (windows -> panes), probing resumers.
save_collect_session() {
	local rep=$1 group=$2 US=$'\x1f'
	local widx wid wname wauto wlayout wactive wwidth wheight pidx pid ppid pcmd ppath pactive ptitle probe
	local panes=()
	while IFS=$US read -r widx wid wname wauto wlayout wactive wwidth wheight pidx pid ppid pcmd ppath pactive ptitle; do
		[ -n "$pid" ] || continue
		probe=$(resumers_probe "$pid" "$ppid" "$wid" "$rep" "$ppath" "$pcmd")
		panes+=("$(jq -cn \
			--argjson widx "$widx" --arg wid "$wid" --arg wname "$wname" --argjson wauto "$( [ "$wauto" = 1 ] && echo true || echo false )" \
			--arg wlayout "$wlayout" --argjson wactive "$( [ "$wactive" = 1 ] && echo true || echo false )" \
			--argjson wwidth "${wwidth:-0}" --argjson wheight "${wheight:-0}" \
			--argjson pidx "$pidx" --arg pid "$pid" --argjson ppid "$ppid" --arg pcmd "$pcmd" --arg ppath "$ppath" \
			--argjson pactive "$( [ "$pactive" = 1 ] && echo true || echo false )" --arg ptitle "$ptitle" --argjson probe "$probe" \
			'{window_index: $widx, window_id: $wid, window_name: $wname, automatic_rename: $wauto, layout: $wlayout,
			  window_active: $wactive, width: $wwidth, height: $wheight, index: $pidx, id: $pid, pid: $ppid, command: $pcmd, cwd: $ppath, active: $pactive,
			  title: $ptitle, resumer: ($probe.resumer // null), restore_cmd: ($probe.cmd // null),
			  restore_cwd: (if ($probe.cwd // "") == "" then $ppath else $probe.cwd end), meta: ($probe.meta // {})}')")
	done < <(tmux_cmd list-panes -s -t "=$rep" -F "#{window_index}	#{window_id}	#{window_name}	#{automatic-rename}	#{window_layout}	#{window_active}	#{window_width}	#{window_height}	#{pane_index}	#{pane_id}	#{pane_pid}	#{pane_current_command}	#{pane_current_path}	#{pane_active}	#{pane_title}" | tr '\t' '\037')
	[ ${#panes[@]} -gt 0 ] || return 1
	printf '%s\n' "${panes[@]}" | jq -s --arg name "$group" --arg group "$group" --arg rep "$rep" '
		group_by(.window_index) | map({
			index: .[0].window_index, id: .[0].window_id, name: .[0].window_name,
			automatic_rename: .[0].automatic_rename, layout: .[0].layout, active: .[0].window_active,
			width: .[0].width, height: .[0].height,
			panes: (sort_by(.index) | map({index, id, pid, cwd, command, active, title, resumer, restore_cmd, restore_cwd, meta}))
		}) as $windows
		| {name: $name, group: $group, saved_from: $rep,
		   active_window: (($windows | map(select(.active)) | .[0].index) // ($windows[0].index)),
		   windows: $windows}'
}

# save_collect: the whole snapshot document on stdout; returns 1 when there is nothing to save.
save_collect() {
	local US=$'\x1f' name group sessions=() s
	while IFS=$US read -r name group; do
		[ -n "$name" ] || continue
		if s=$(save_collect_session "$name" "$group"); then sessions+=("$s"); fi
	done < <(save_pick_sessions)
	[ ${#sessions[@]} -gt 0 ] || return 1
	printf '%s\n' "${sessions[@]}" | jq -s --arg saved_at "$(date -Is)" --arg boot "$(boot_id)" \
		--arg tmux "$(tmux_version)" --arg host "$(hostname)" \
		'{version: 1, saved_at: $saved_at, boot_id: $boot, tmux_version: $tmux, hostname: $host, sessions: .}'
}

# save_restore_pending: the newest snapshot is from a previous boot and no restore has had its
# chance on this server yet (restore writes the marker). Overwriting it now would lose the
# workspace that is about to be brought back.
save_restore_pending() {
	local last
	[ "${AUTO_RESTORE:-reboot}" != never ] || return 1
	last=$(snapshot_dir)/last.json
	[ -e "$last" ] || return 1
	[ "$(jq -r '.boot_id // ""' "$last" 2>/dev/null)" != "$(boot_id)" ] || return 1
	has_server || return 1
	[ ! -e "$(restore_marker)" ]
}

# save_unchanged JSON: the newest snapshot would restore the same workspace. Compared without
# what changes all the time: saved_at, pane titles (agents rewrite theirs constantly), pane
# commands, and the names of automatically renamed windows; the in-place rewrite of an
# unchanged save keeps those current.
save_unchanged() {
	local last view
	last=$(snapshot_dir)/last.json
	[ -e "$last" ] || return 1
	view='del(.saved_at) | .sessions[].windows[] |= ((if .automatic_rename then del(.name) else . end) | .panes[] |= del(.title, .command))'
	[ "$(jq -cS "$view" "$last" 2>/dev/null)" = "$(printf '%s' "$1" | jq -cS "$view")" ]
}

# save_input_since_last: an attached client had input after the newest snapshot was written
# (or confirmed unchanged), or there is no snapshot yet.
save_input_since_last() {
	local last t a newest=0
	last=$(snapshot_dir)/last.json
	[ -e "$last" ] || return 0
	t=$(stat -Lc %Y "$last")
	while IFS= read -r a; do
		if [ "${a:-0}" -gt "$newest" ]; then newest=$a; fi
	done < <(tmux_cmd list-clients -F '#{client_activity}' 2>/dev/null)
	[ "$newest" -gt "$t" ]
}

# save_scrollback JSON: capture the last SCROLLBACK_LINES lines of every pane in the snapshot
# into a new directory, one <pane id>.gz each, and print its path; nothing when SCROLLBACK_LINES
# is 0. A pane in a full-screen program contributes the screen it returns to, not the program's.
save_scrollback() {
	local lines=${SCROLLBACK_LINES:-0} dir id alt hist text
	[ "$lines" -gt 0 ] 2>/dev/null || return 0
	mkdir -p "$(snapshot_dir)"
	dir=$(mktemp -d "$(snapshot_dir)/.tmp.XXXXXX")
	while IFS= read -r id; do
		read -r alt hist < <(tmux_cmd display -p -t "$id" '#{alternate_on} #{history_size}' 2>/dev/null) || continue
		# -E -1 without any history would capture the first visible line instead
		text=$(
			if [ "$alt" != 1 ]; then
				tmux_cmd capture-pane -p -e -J -t "$id" -S "-$lines"
			else
				if [ "${hist:-0}" -gt 0 ]; then tmux_cmd capture-pane -p -e -J -t "$id" -S "-$lines" -E -1; fi
				tmux_cmd capture-pane -p -e -J -a -t "$id"
			fi 2>/dev/null
		) || true
		[ -n "$text" ] || continue
		printf '%s\n\033[0m' "$text" | gzip > "$dir/${id#%}.gz"
	done < <(printf '%s' "$1" | jq -r '.sessions[].windows[].panes[].id')
	printf '%s' "$dir"
}

# save_now [--force]: write a snapshot unless a guard says the moment is wrong. An unchanged
# workspace rewrites the newest snapshot in place instead, so identical copies do not push older
# states out of KEEP_SNAPSHOTS; --force writes anyway.
save_now() {
	local force=0
	[ "${1:-}" = "--force" ] && force=1
	if ! has_server; then log_debug "no tmux server; nothing to save"; return 0; fi
	if [ $force -eq 0 ] && restore_in_progress; then log_debug "a restore is in progress; skipping save"; return 0; fi
	if [ $force -eq 0 ] && save_restore_pending; then
		log_info "the snapshot is from a previous boot and no restore ran on this server yet; keeping it (tmux-workspace-resume restore, or save --force)"
		return 0
	fi
	local json scrollback
	if ! json=$(save_collect); then log_debug "no panes found; nothing to save"; return 0; fi
	scrollback=$(save_scrollback "$json")
	if [ $force -eq 0 ] && save_unchanged "$json"; then
		printf '%s' "$json" | snapshot_refresh "$scrollback"
		log_debug "workspace unchanged since $(basename "$(readlink -f "$(snapshot_dir)/last.json")"); not writing a new snapshot"
		return 0
	fi
	local file; file=$(printf '%s' "$json" | snapshot_write "$scrollback") || return 1
	log_info "saved $(snapshot_summary "$file") -> $file"
}

# save_debounced: coalesce a burst of hook events into one save after SAVE_DEBOUNCE_S.
save_debounced() {
	local rd; rd=$(runtime_dir)
	touch "$rd/dirty"
	exec 9>"$rd/save.lock"
	flock -n 9 || exit 0
	while [ -e "$rd/dirty" ]; do
		rm -f "$rd/dirty"
		sleep "${SAVE_DEBOUNCE_S:-3}"
		save_now || true
	done
	flock -u 9
	# An event that arrived between the loop test and the unlock would otherwise wait for the timer.
	[ -e "$rd/dirty" ] && exec "$TWR_BIN" save --debounce --quiet
	return 0
}

cmd_save() {
	local debounce=0 force=0 timer=0
	while [ $# -gt 0 ]; do
		case $1 in
			--debounce) debounce=1 ;;
			--force) force=1 ;;
			--timer) timer=1 ;;
			-q|--quiet) quiet_on ;;
			*) die "usage: tmux-workspace-resume save [--debounce] [--force] [--timer]" ;;
		esac
		shift
	done
	if [ $timer -eq 1 ] && [ "${TIMER_SAVE:-always}" = after-input ] && ! save_input_since_last; then
		log_debug "no client input since the last snapshot; skipping the timer save (TIMER_SAVE=after-input)"
		return 0
	fi
	if [ $debounce -eq 1 ]; then
		save_debounced
	elif [ $force -eq 1 ]; then
		save_now --force
	else
		save_now
	fi
}
