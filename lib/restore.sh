# shellcheck shell=bash
# ai-revive — rebuild sessions, windows and panes from a snapshot and relaunch their programs.
# SPDX-License-Identifier: GPL-3.0-or-later

# restore_find_fresh_session: the name of the placeholder session tmux/byobu creates on a fresh
# start (one session, one window, one pane, nothing but a shell in it), or nothing.
restore_find_fresh_session() {
	local US=$'\x1f' n name created cmd pid child
	n=$(tmux_cmd list-sessions -F x 2>/dev/null | wc -l)
	[ "$n" -eq 1 ] || return 0
	IFS=$US read -r name created < <(tmux_cmd list-sessions -F "#{session_name}	#{session_created}" | tr '\t' '\037')
	[ "$(tmux_cmd list-panes -s -t "=$name" -F x | wc -l)" -eq 1 ] || return 0
	# Younger than 20 s: byobu-shell may still be printing its motd before exec'ing the real shell.
	if [ $(( $(date +%s) - created )) -le 20 ]; then printf '%s' "$name"; return 0; fi
	IFS=$US read -r cmd pid < <(tmux_cmd list-panes -s -t "=$name" -F "#{pane_current_command}	#{pane_pid}" | tr '\t' '\037')
	is_shell "$cmd" || return 0
	for child in $(children_of "$pid"); do
		is_shell "$(proc_argv0 "$child")" || return 0
	done
	printf '%s' "$name"
}

# restore_wait_for_shell PANE_ID: until the pane's foreground process is a shell (SHELL_WAIT_S).
restore_wait_for_shell() {
	local n=$(( ${SHELL_WAIT_S:-10} * 10 )) cmd
	while :; do
		cmd=$(tmux_cmd display -p -t "$1" '#{pane_current_command}' 2>/dev/null || true)
		is_shell "$cmd" && return 0
		n=$((n - 1)); [ "$n" -gt 0 ] || return 1
		sleep 0.1
	done
}

# say LINE: the restore plan goes to stdout on a dry run and to the log file on a real one.
say() {
	if [ "${RESTORE_DRY:-0}" = 1 ]; then printf '%s\n' "$*"; else printf '%s\n' "$*" >> "$(log_file)"; fi
}

_ms_sleep() { [ "${1:-0}" -gt 0 ] 2>/dev/null && sleep "$(awk "BEGIN{print $1/1000}")"; return 0; }

# restore_session FILE INDEX DRY LAYOUT_ONLY: restores .sessions[INDEX]. Appends
# "pane_id<US>cwd<US>cmd" lines for the programs to relaunch to the global RESTORE_CMDS array.
restore_session() {
	local file=$1 i=$2 dry=$3 layout_only=$4 US=$'\x1f'
	local sess nwin placeholder="" created=0 maxidx fresh
	sess=$(jq -r ".sessions[$i].name" "$file")
	nwin=$(jq ".sessions[$i].windows | length" "$file")
	maxidx=$(jq ".sessions[$i].windows | map(.index) | max" "$file")
	say "session '$sess' ($nwin windows)"

	fresh=$(restore_find_fresh_session)
	if ! tmux_cmd has-session -t "=$sess" 2>/dev/null; then
		if [ "$dry" = 1 ]; then
			if [ -n "$fresh" ]; then say "  would rename fresh session '$fresh' to '$sess'"; else say "  would create session '$sess'"; fi
		elif [ -n "$fresh" ]; then
			tmux_cmd rename-session -t "=$fresh" "$sess"
			placeholder=$(tmux_cmd display -p -t "=$sess:" '#{window_id}')
			log_info "reusing fresh session '$fresh' as '$sess'"
		else
			placeholder=$(tmux_cmd new-session -d -s "$sess" -x 200 -y 50 -P -F '#{window_id}')
			log_info "created session '$sess'"
		fi
	elif [ "$fresh" = "$sess" ]; then
		# the placeholder session already carries the saved name (byobu's first session is "0")
		if [ "$dry" = 1 ]; then
			say "  would reuse fresh session '$sess'"
		else
			placeholder=$(tmux_cmd display -p -t "=$sess:" '#{window_id}')
			log_info "reusing fresh session '$sess'"
		fi
	fi
	[ -z "$placeholder" ] || tmux_cmd move-window -s "$placeholder" -t "=$sess:$((maxidx + 1000))"

	local w widx wname wauto wlayout _wactive npanes wid last p pcwd pnew cwd0 args pane_ids line new_id old_idx
	for ((w = 0; w < nwin; w++)); do
		IFS=$US read -r widx wname wauto wlayout _wactive npanes < <(jq -r ".sessions[$i].windows[$w]
			| [.index, .name, (.automatic_rename|tostring), .layout, (.active|tostring), (.panes|length)] | join(\"\\u001f\")" "$file")
		if tmux_cmd list-windows -t "=$sess" -F '#{window_index}' 2>/dev/null | grep -qx "$widx"; then
			say "  window $widx '$wname': already exists, skipped"
			continue
		fi
		cwd0=$(jq -r ".sessions[$i].windows[$w].panes[0].cwd" "$file")
		[ -d "$cwd0" ] || { log_warn "window $widx: directory '$cwd0' is gone, using \$HOME"; cwd0=$HOME; }
		say "  window $widx '$wname' ($npanes panes)"
		if [ "$dry" = 1 ]; then
			wid=""
		else
			args=(new-window -d -P -F '#{window_id}' -t "=$sess:$widx" -c "$cwd0")
			[ "$wauto" = false ] && args+=(-n "$wname")
			wid=$(tmux_cmd "${args[@]}")
			created=$((created + 1))
			last=$(tmux_cmd display -p -t "$wid" '#{pane_id}')
		fi
		# Split from the newest pane each time: tmux inserts the new pane after its target, so the
		# pane list order equals the saved index order, which is what select-layout maps cells onto.
		for ((p = 1; p < npanes; p++)); do
			pcwd=$(jq -r ".sessions[$i].windows[$w].panes[$p].cwd" "$file")
			[ -d "$pcwd" ] || { log_warn "window $widx pane $p: directory '$pcwd' is gone, using \$HOME"; pcwd=$HOME; }
			[ "$dry" = 1 ] && continue
			last=$(tmux_cmd split-window -d -P -F '#{pane_id}' -t "$last" -c "$pcwd")
			tmux_cmd select-layout -t "$wid" tiled >/dev/null
		done
		if [ "$dry" != 1 ]; then
			if [ "$npanes" -gt 1 ] || [ -n "$wlayout" ]; then
				tmux_cmd select-layout -t "$wid" "$wlayout" >/dev/null 2>&1 ||
					{ log_warn "window $widx: could not apply saved layout, using tiled"; tmux_cmd select-layout -t "$wid" tiled >/dev/null; }
			fi
			[ "$wauto" = true ] && tmux_cmd set-option -w -t "$wid" automatic-rename on
		fi
		# map saved pane index -> new pane id (creation order == index order == layout leaf order)
		pane_ids=()
		if [ "$dry" != 1 ]; then
			while IFS= read -r line; do pane_ids+=("$line"); done < <(tmux_cmd list-panes -t "$wid" -F '#{pane_id}')
		fi
		for ((p = 0; p < npanes; p++)); do
			IFS=$US read -r old_idx pcwd pnew < <(jq -r ".sessions[$i].windows[$w].panes[$p]
				| [(.index|tostring), (.restore_cwd // .cwd), (.restore_cmd // \"\")] | join(\"\\u001f\")" "$file")
			new_id=${pane_ids[$p]:-"(pane $p)"}
			if [ "$dry" != 1 ] && jq -e ".sessions[$i].windows[$w].panes[$p].active" "$file" >/dev/null; then
				tmux_cmd select-pane -t "$new_id"
			fi
			if [ -n "$pnew" ]; then
				say "    pane $old_idx -> $new_id: cd $(shell_quote "$pcwd") && $pnew"
				[ "$layout_only" = 1 ] || RESTORE_CMDS+=("$new_id$US$pcwd$US$pnew")
			fi
		done
	done

	if [ "$dry" != 1 ]; then
		local active_idx; active_idx=$(jq -r ".sessions[$i].active_window" "$file")
		tmux_cmd select-window -t "=$sess:$active_idx" 2>/dev/null || true
		if [ -n "$placeholder" ] && [ "$created" -gt 0 ]; then
			tmux_cmd kill-window -t "$placeholder" 2>/dev/null || true
		fi
	fi
}

restore_send_commands() {
	local US=$'\x1f' entry pane cwd cmd
	for entry in "${RESTORE_CMDS[@]}"; do
		IFS=$US read -r pane cwd cmd <<< "$entry"
		if ! restore_wait_for_shell "$pane"; then
			log_warn "pane $pane: no shell prompt after ${SHELL_WAIT_S}s, not running: $cmd"
			continue
		fi
		_ms_sleep "${RESTORE_DELAY_MS:-300}"
		tmux_cmd send-keys -t "$pane" -l -- "cd $(shell_quote "$cwd") && $cmd"
		tmux_cmd send-keys -t "$pane" Enter
		log_info "pane $pane: $cmd"
		_ms_sleep "${RESTORE_STAGGER_MS:-300}"
	done
}

restore_from_file() {
	local file=$1 dry=$2 layout_only=$3 rd nsess i
	rd=$(runtime_dir)
	RESTORE_CMDS=()
	RESTORE_DRY=$dry
	if [ "$dry" != 1 ]; then
		echo $$ > "$rd/restoring"
		# shellcheck disable=SC2064
		trap "rm -f '$rd/restoring'" EXIT
	fi
	nsess=$(jq '.sessions | length' "$file")
	for ((i = 0; i < nsess; i++)); do
		restore_session "$file" "$i" "$dry" "$layout_only"
	done
	if [ "$dry" != 1 ]; then
		restore_send_commands
		rm -f "$rd/restoring"
		trap - EXIT
		if [ "${RESTORE_SETTLE_S:-0}" -gt 0 ] 2>/dev/null; then
			setsid -f bash -c "sleep $RESTORE_SETTLE_S; exec \"\$0\" save --quiet" "$AI_REVIVE_BIN" </dev/null >/dev/null 2>&1 || true
		fi
		log_info "restored from $file"
	fi
}

cmd_restore() {
	local auto=0 dry=0 layout_only=0 snap="" file
	while [ $# -gt 0 ]; do
		case $1 in
			--auto) auto=1 ;;
			--dry-run|-n) dry=1 ;;
			--layout-only) layout_only=1 ;;
			-q|--quiet) quiet_on ;;
			-*) die "usage: ai-revive restore [--auto] [--dry-run] [--layout-only] [snapshot]" ;;
			*) snap=$1 ;;
		esac
		shift
	done
	file=$(snapshot_resolve "$snap") || return 1
	if [ $auto -eq 1 ]; then
		[ "${AI_REVIVE_NO_RESTORE:-0}" = 1 ] && { log_info "AI_REVIVE_NO_RESTORE is set; not restoring"; return 0; }
		[ "$AUTO_RESTORE" = never ] && { log_debug "AUTO_RESTORE=never"; return 0; }
		wait_for_server 5 || { log_info "no tmux server appeared; nothing to restore into"; return 0; }
		local spid marker
		spid=$(server_pid)
		marker=$(runtime_dir)/restored-$spid
		[ -e "$marker" ] && { log_debug "already ran for server $spid"; return 0; }
		touch "$marker"
		if [ "$AUTO_RESTORE" = reboot ] && [ "$(jq -r '.boot_id // ""' "$file")" = "$(boot_id)" ]; then
			log_info "snapshot is from this boot; not auto-restoring (AUTO_RESTORE=reboot)"
			return 0
		fi
		quiet_on
	else
		wait_for_server "${SHELL_WAIT_S:-10}" || die "no tmux server running"
	fi
	if [ $dry -eq 1 ]; then
		echo "dry run: $file ($(snapshot_summary "$file"))"
		restore_from_file "$file" 1 "$layout_only"
	else
		restore_from_file "$file" 0 "$layout_only"
	fi
}
