# shellcheck shell=bash
# ai-revive — snapshot the running tmux server.
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
	local widx wid wname wauto wlayout wactive pidx pid ppid pcmd ppath pactive ptitle probe
	local panes=()
	while IFS=$US read -r widx wid wname wauto wlayout wactive pidx pid ppid pcmd ppath pactive ptitle; do
		[ -n "$pid" ] || continue
		probe=$(resumers_probe "$pid" "$ppid" "$wid" "$rep" "$ppath" "$pcmd")
		panes+=("$(jq -cn \
			--argjson widx "$widx" --arg wid "$wid" --arg wname "$wname" --argjson wauto "$( [ "$wauto" = 1 ] && echo true || echo false )" \
			--arg wlayout "$wlayout" --argjson wactive "$( [ "$wactive" = 1 ] && echo true || echo false )" \
			--argjson pidx "$pidx" --arg pid "$pid" --argjson ppid "$ppid" --arg pcmd "$pcmd" --arg ppath "$ppath" \
			--argjson pactive "$( [ "$pactive" = 1 ] && echo true || echo false )" --arg ptitle "$ptitle" --argjson probe "$probe" \
			'{window_index: $widx, window_id: $wid, window_name: $wname, automatic_rename: $wauto, layout: $wlayout,
			  window_active: $wactive, index: $pidx, id: $pid, pid: $ppid, command: $pcmd, cwd: $ppath, active: $pactive,
			  title: $ptitle, resumer: ($probe.resumer // null), restore_cmd: ($probe.cmd // null),
			  restore_cwd: (if ($probe.cwd // "") == "" then $ppath else $probe.cwd end), meta: ($probe.meta // {})}')")
	done < <(tmux_cmd list-panes -s -t "=$rep" -F "#{window_index}	#{window_id}	#{window_name}	#{automatic-rename}	#{window_layout}	#{window_active}	#{pane_index}	#{pane_id}	#{pane_pid}	#{pane_current_command}	#{pane_current_path}	#{pane_active}	#{pane_title}" | tr '\t' '\037')
	[ ${#panes[@]} -gt 0 ] || return 1
	printf '%s\n' "${panes[@]}" | jq -s --arg name "$group" --arg group "$group" --arg rep "$rep" '
		group_by(.window_index) | map({
			index: .[0].window_index, id: .[0].window_id, name: .[0].window_name,
			automatic_rename: .[0].automatic_rename, layout: .[0].layout, active: .[0].window_active,
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

# save_is_blank JSON: true for the "just started" shape (1 session, 1 window, 1 pane, no command).
save_is_blank() {
	printf '%s' "$1" | jq -e '
		(.sessions | length) == 1 and ([.sessions[].windows[]] | length) == 1
		and ([.sessions[].windows[].panes[]] | length) == 1
		and ([.sessions[].windows[].panes[] | select(.restore_cmd != null)] | length) == 0' >/dev/null 2>&1
}

# save_now [--force]: write a snapshot unless a guard says the moment is wrong.
save_now() {
	local force=0
	[ "${1:-}" = "--force" ] && force=1
	local rd; rd=$(runtime_dir)
	if ! has_server; then log_debug "no tmux server; nothing to save"; return 0; fi
	if [ $force -eq 0 ] && [ -r "$rd/restoring" ] && proc_alive "$(cat "$rd/restoring" 2>/dev/null || echo 0)"; then
		log_debug "a restore is in progress; skipping save"; return 0
	fi
	local json
	if ! json=$(save_collect); then log_debug "no panes found; nothing to save"; return 0; fi
	if [ $force -eq 0 ] && save_is_blank "$json" && [ -e "$(snapshot_dir)/last.json" ] &&
		! save_is_blank "$(cat "$(snapshot_dir)/last.json")"; then
		log_info "server looks freshly started; keeping the previous snapshot (use --force to overwrite)"
		return 0
	fi
	local file; file=$(printf '%s' "$json" | snapshot_write) || return 1
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
	[ -e "$rd/dirty" ] && exec "$AI_REVIVE_BIN" save --debounce --quiet
	return 0
}

cmd_save() {
	local debounce=0 force=0
	while [ $# -gt 0 ]; do
		case $1 in
			--debounce) debounce=1 ;;
			--force) force=1 ;;
			-q|--quiet) quiet_on ;;
			*) die "usage: ai-revive save [--debounce] [--force]" ;;
		esac
		shift
	done
	if [ $debounce -eq 1 ]; then
		save_debounced
	elif [ $force -eq 1 ]; then
		save_now --force
	else
		save_now
	fi
}
