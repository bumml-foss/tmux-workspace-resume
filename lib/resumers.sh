# shellcheck shell=bash
# ai-revive — resumer discovery and probing. A resumer is an executable that, given a pane,
# decides whether it knows how to relaunch the program running there and prints the command.
# Contract: see ai-revive-resumers(7). Shipped ones live in $AI_REVIVE_HOME/resumers/, user ones
# in $XDG_CONFIG_HOME/ai-revive/resumers/ (same basename = override). Sorted, first claim wins.
# SPDX-License-Identifier: GPL-3.0-or-later

# resumers_list: "basename<TAB>path" lines for the effective set.
resumers_list() {
	local -A seen=()
	local d f b
	for d in "$(config_dir)/resumers" "$AI_REVIVE_HOME/resumers"; do
		[ -d "$d" ] || continue
		for f in "$d"/*; do
			[ -f "$f" ] && [ -x "$f" ] || continue
			b=$(basename "$f")
			[ -z "${seen[$b]+x}" ] || continue
			seen[$b]=$f
		done
	done
	for b in "${!seen[@]}"; do printf '%s\t%s\n' "$b" "${seen[$b]}"; done | sort
}

# resumers_probe PANE_ID PANE_PID WINDOW_ID SESSION CWD COMMAND
# Prints {"resumer":..,"cmd":..,"cwd":..,"meta":{}} for the first resumer that claims the pane,
# or {} when none does. Resumer errors are logged and treated as "does not claim".
resumers_probe() {
	local pane_id=$1 pane_pid=$2 window_id=$3 session=$4 cwd=$5 command=$6
	local b path out rc
	while IFS=$'\t' read -r b path; do
		[ -n "$path" ] || continue
		out=$(AI_REVIVE_PANE_ID=$pane_id AI_REVIVE_PANE_PID=$pane_pid AI_REVIVE_WINDOW_ID=$window_id \
			AI_REVIVE_SESSION=$session AI_REVIVE_CWD=$cwd AI_REVIVE_COMMAND=$command \
			timeout 5 "$path" probe 2>>"$(log_file)") && rc=0 || rc=$?
		if [ $rc -eq 0 ]; then
			if printf '%s' "$out" | jq -e '.cmd | type == "string" and length > 0' >/dev/null 2>&1; then
				printf '%s' "$out" | jq -c --arg r "${b#[0-9][0-9]-}" \
					'{resumer: $r, cmd: .cmd, cwd: (.cwd // ""), meta: (.meta // {})}'
				return 0
			fi
			log_warn "resumer $b printed unusable output for pane $pane_id; ignoring it"
		elif [ $rc -ne 1 ]; then
			log_warn "resumer $b failed with exit $rc for pane $pane_id; ignoring it"
		fi
	done < <(resumers_list)
	printf '{}'
}

cmd_resumers() {
	local sub=${1:-list}
	case $sub in
		list)
			local b path info
			while IFS=$'\t' read -r b path; do
				info=$("$path" info 2>/dev/null || echo "(no description)")
				printf '%-14s %s\n               %s\n' "$b" "$path" "$info"
			done < <(resumers_list)
			;;
		probe)
			local pane=${2:-}
			[ -n "$pane" ] || die "usage: ai-revive resumers probe <pane-id>"
			has_server || die "no tmux server"
			local US=$'\x1f' pane_id pane_pid window_id session cwd command
			IFS=$US read -r pane_id pane_pid window_id session cwd command < <(tmux_cmd display -p -t "$pane" \
				"#{pane_id}	#{pane_pid}	#{window_id}	#{session_name}	#{pane_current_path}	#{pane_current_command}" | tr '\t' '\037')
			resumers_probe "$pane_id" "$pane_pid" "$window_id" "$session" "$cwd" "$command" | jq .
			;;
		*) die "usage: ai-revive resumers [list|probe <pane-id>]" ;;
	esac
}
