# shellcheck shell=bash
# tmux-workspace-resume — rebuild sessions, windows and panes from a snapshot and relaunch their programs.
# SPDX-License-Identifier: GPL-3.0-or-later

# say LINE: the restore plan goes to stdout on a dry run and to the log file on a real one.
say() {
	if [ "${RESTORE_DRY:-0}" = 1 ]; then printf '%s\n' "$*"; else printf '%s\n' "$*" >> "$(log_file)"; fi
}

_ms_sleep() { [ "${1:-0}" -gt 0 ] 2>/dev/null && sleep "$(awk "BEGIN{print $1/1000}")"; return 0; }

# restore_wait_idle PANE: until the pane's shell has no children (prompt is up), at most SHELL_WAIT_S.
restore_wait_idle() {
	local n=$(( ${SHELL_WAIT_S:-10} * 10 ))
	while ! pane_idle "$1"; do
		n=$((n - 1)); [ "$n" -gt 0 ] || return 1
		sleep 0.1
	done
}

# restore_apply_layout WINDOW_ID LAYOUT INDEX: apply the saved layout scaled to the window's
# current size (see lib/layout.sh for why); "tiled" when it cannot be scaled or applied.
restore_apply_layout() {
	local wid=$1 layout=$2 widx=$3 size scaled
	size=$(tmux_cmd display -p -t "$wid" '#{window_width} #{window_height}')
	if scaled=$(layout_scale "$layout" "${size% *}" "${size#* }" 2>/dev/null) &&
		tmux_cmd select-layout -t "$wid" "$scaled" >/dev/null 2>&1; then
		return 0
	fi
	log_warn "window $widx: saved layout does not fit ${size% *}x${size#* }, using tiled"
	tmux_cmd select-layout -t "$wid" tiled >/dev/null
}

# restore_session FILE INDEX DRY LAYOUT_ONLY: restores .sessions[INDEX]. Appends
# "pane_id<US>cwd<US>cmd" lines for the programs to relaunch to the global RESTORE_CMDS array.
#
# Where the windows go: into the saved session if it exists. Otherwise the first missing session
# takes over the server's only session, when there is exactly one (the one tmux/byobu just
# created, or the one the user is sitting in): it is renamed so the attached client follows.
# Further missing sessions are created at their saved size.
#
# The placeholder window: a session this restore took over always has one, and a pre-existing
# session's single one-pane window counts when it is idle (otherwise it is a restored window
# whose program is running, and touching it would launch that program twice). The placeholder
# is moved out of the way, and at the end removed if idle, kept after the last window if not.
restore_session() {
	local file=$1 i=$2 dry=$3 layout_only=$4 US=$'\x1f'
	local sess nwin placeholder="" placeholder_idx="" placeholder_ours=0 created=0 maxidx size taken=0
	sess=$(jq -r ".sessions[$i].name" "$file")
	nwin=$(jq ".sessions[$i].windows | length" "$file")
	maxidx=$(jq ".sessions[$i].windows | map(.index) | max" "$file")
	say "session '$sess' ($nwin windows)"

	if ! tmux_cmd has-session -t "=$sess" 2>/dev/null; then
		if [ -n "$RESTORE_SPARE_SESSION" ]; then
			if [ "$dry" = 1 ]; then
				say "  would rename session '$RESTORE_SPARE_SESSION' to '$sess'"
			else
				tmux_cmd rename-session -t "=$RESTORE_SPARE_SESSION" "$sess"
				log_info "reusing session '$RESTORE_SPARE_SESSION' as '$sess'"
			fi
			RESTORE_SPARE_SESSION=""
			taken=1
		elif [ "$dry" = 1 ]; then
			say "  would create session '$sess'"
		else
			size=$(jq -r ".sessions[$i].windows[0] | \"\\(.width // 200) \\(.height // 50)\"" "$file")
			[ "${size% *}" -gt 0 ] 2>/dev/null || size="200 50"
			tmux_cmd new-session -d -s "$sess" -x "${size% *}" -y "${size#* }" >/dev/null
			log_info "created session '$sess' (${size% *}x${size#* })"
			taken=1
		fi
	elif [ "$RESTORE_SPARE_SESSION" = "$sess" ]; then
		RESTORE_SPARE_SESSION=""        # pre-existing: its window is a placeholder only if idle
	fi
	if [ "$dry" != 1 ] && [ "$(tmux_cmd list-panes -s -t "=$sess" -F x | wc -l)" -eq 1 ]; then
		IFS=$US read -r placeholder placeholder_idx < <(tmux_cmd display -p -t "=$sess:" "#{window_id}	#{window_index}" | tr '\t' '\037')
		if [ "$taken" = 1 ] || restore_wait_idle "=$sess:"; then
			tmux_cmd move-window -s "$placeholder" -t "=$sess:$((maxidx + 1000))"
			pane_is_ours "$placeholder" && placeholder_ours=1
		else
			placeholder=""
		fi
	fi

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
			if ! wid=$(tmux_cmd "${args[@]}" 2>/dev/null); then
				log_warn "window $widx '$wname': could not create it; skipping"
				continue
			fi
			created=$((created + 1))
			last=$(tmux_cmd display -p -t "$wid" '#{pane_id}')
		fi
		# Split from the newest pane each time: tmux inserts the new pane after its target, so the
		# pane list order equals the saved index order, which is what select-layout maps cells onto.
		for ((p = 1; p < npanes; p++)); do
			pcwd=$(jq -r ".sessions[$i].windows[$w].panes[$p].cwd" "$file")
			[ -d "$pcwd" ] || { log_warn "window $widx pane $p: directory '$pcwd' is gone, using \$HOME"; pcwd=$HOME; }
			[ "$dry" = 1 ] && continue
			if ! last=$(tmux_cmd split-window -d -P -F '#{pane_id}' -t "$last" -c "$pcwd" 2>/dev/null); then
				log_warn "window $widx: could not create pane $p (window too small?); restoring the rest"
				break
			fi
			tmux_cmd select-layout -t "$wid" tiled >/dev/null
		done
		if [ "$dry" != 1 ]; then
			if [ "$npanes" -gt 1 ] && [ -n "$wlayout" ]; then
				restore_apply_layout "$wid" "$wlayout" "$widx"
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
		if [ -n "$placeholder" ]; then
			if [ "$created" -eq 0 ]; then
				tmux_cmd move-window -s "$placeholder" -t "=$sess:$placeholder_idx" 2>/dev/null || true
			elif [ "$placeholder_ours" = 1 ]; then
				# this restore was typed into that window; killing it would kill the restore
				tmux_cmd move-window -s "$placeholder" -t "=$sess:$((maxidx + 1))" 2>/dev/null || true
				log_info "kept the window the restore was started from as window $((maxidx + 1))"
			elif restore_wait_idle "$placeholder"; then
				# byobu-shell may still be printing its motd, hence the bounded wait
				tmux_cmd kill-window -t "$placeholder" 2>/dev/null || true
			else
				tmux_cmd move-window -s "$placeholder" -t "=$sess:$((maxidx + 1))" 2>/dev/null || true
				log_info "kept the window that was open before the restore as window $((maxidx + 1)) (something is running in it)"
			fi
		fi
	fi
}

restore_send_commands() {
	local US=$'\x1f' entry pane cwd cmd
	for entry in "${RESTORE_CMDS[@]}"; do
		IFS=$US read -r pane cwd cmd <<< "$entry"
		if ! restore_wait_idle "$pane"; then
			log_warn "pane $pane: no idle shell after ${SHELL_WAIT_S}s, not running: $cmd"
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
	local file=$1 dry=$2 layout_only=$3 nsess i
	RESTORE_CMDS=()
	RESTORE_DRY=$dry
	# the server's only session (if it has exactly one) may be taken over by the first missing session
	RESTORE_SPARE_SESSION=""
	if [ "$(tmux_cmd list-sessions -F x 2>/dev/null | wc -l)" -eq 1 ]; then
		RESTORE_SPARE_SESSION=$(tmux_cmd list-sessions -F '#{session_name}')
	fi
	if [ "$dry" != 1 ]; then
		# held until this process exits; save_now skips while it is held
		exec 8>"$(restore_lock_file)"
		flock -n 8 || die "another restore is running"
	fi
	nsess=$(jq '.sessions | length' "$file")
	for ((i = 0; i < nsess; i++)); do
		restore_session "$file" "$i" "$dry" "$layout_only"
	done
	if [ "$dry" != 1 ]; then
		restore_send_commands
		touch "$(restore_marker)"
		flock -u 8
		if [ "$layout_only" != 1 ] && [ "${RESTORE_SETTLE_S:-0}" -gt 0 ] 2>/dev/null; then
			setsid -f bash -c "sleep $RESTORE_SETTLE_S; exec \"\$0\" save --quiet" "$TWR_BIN" </dev/null >/dev/null 2>&1 || true
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
			-*) die "usage: tmux-workspace-resume restore [--auto] [--dry-run] [--layout-only] [snapshot]" ;;
			*) snap=$1 ;;
		esac
		shift
	done
	file=$(snapshot_resolve "$snap") || return 1
	if [ $auto -eq 1 ]; then
		[ "$AUTO_RESTORE" = never ] && { log_debug "AUTO_RESTORE=never"; return 0; }
		wait_for_server 5 || { log_info "no tmux server appeared; nothing to restore into"; return 0; }
		# one attempt per server; a decision not to restore also lets saves proceed (completion marker)
		[ -e "$(restore_attempt_marker)" ] && { log_debug "already ran for this server"; return 0; }
		touch "$(restore_attempt_marker)"
		if [ "${TWR_NO_RESTORE:-0}" = 1 ]; then
			log_info "TWR_NO_RESTORE is set; not restoring"
			touch "$(restore_marker)"
			return 0
		fi
		if [ "$AUTO_RESTORE" = reboot ] && [ "$(jq -r '.boot_id // ""' "$file")" = "$(boot_id)" ]; then
			log_info "snapshot is from this boot; not auto-restoring (AUTO_RESTORE=reboot)"
			touch "$(restore_marker)"
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
