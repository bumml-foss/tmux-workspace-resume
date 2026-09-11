# shellcheck shell=bash
# ai-revive — helpers for resumers of AI coding agents that, unlike Claude Code, do not record
# which tmux pane they run in. The resumer finds the agent's process under the pane's shell and
# identifies its session by (1) a session file the process holds open, (2) the newest session
# file created after the process started, in the process's directory, or (3) gives up on the
# session and re-emits the command line the agent was started with.
# SPDX-License-Identifier: GPL-3.0-or-later

# proc_descendants PID: every descendant pid, breadth first.
proc_descendants() {
	local queue=("$1") pid child
	while [ ${#queue[@]} -gt 0 ]; do
		pid=${queue[0]}; queue=("${queue[@]:1}")
		for child in $(children_of "$pid"); do
			printf '%s\n' "$child"
			queue+=("$child")
		done
	done
}
proc_cmdline_text() { tr '\0' ' ' < "/proc/$1/cmdline" 2>/dev/null || true; }
proc_cwd() { readlink -f "/proc/$1/cwd" 2>/dev/null || true; }
# proc_start_epoch PID: start time as seconds since the epoch.
proc_start_epoch() {
	local lstart
	lstart=$(ps -o lstart= -p "$1" 2>/dev/null) || return 1
	[ -n "$lstart" ] || return 1
	date -d "$lstart" +%s
}
# proc_open_paths PID: resolved targets of the process's open file descriptors.
proc_open_paths() {
	local fd
	for fd in /proc/"$1"/fd/*; do readlink -f "$fd" 2>/dev/null || true; done
}

# agent_find_process PANE_PID REGEX: pid of the first process under the pane's shell whose
# command line matches REGEX (node-based CLIs show up as "node /path/to/tool/index.js ...").
agent_find_process() {
	local root=$1 re=$2 pid
	for pid in $(proc_descendants "$root"); do
		if proc_cmdline_text "$pid" | grep -qE -- "$re"; then printf '%s' "$pid"; return 0; fi
	done
	return 1
}

# agent_args_after PID REGEX: the arguments after the argv element matching REGEX (the tool's
# binary or script), shell-quoted, e.g. "--resume 3" out of "node /x/gemini.js --resume 3".
agent_args_after() {
	local pid=$1 re=$2 arg found=0 out=""
	while IFS= read -r -d '' arg; do
		if [ $found -eq 1 ]; then
			out+="${out:+ }$(shell_quote "$arg")"
		elif printf '%s' "$arg" | grep -qE -- "$re"; then
			found=1
		fi
	done < "/proc/$pid/cmdline"
	printf '%s' "$out"
}

# agent_pick START: reads candidate lines "CREATED<TAB>MTIME<TAB>PATH" (epoch seconds; CREATED may be
# empty) and prints the PATH of the best match for a process started at START: the candidate
# created soonest after the process started (a session this process began), else the most
# recently modified one (a session this process resumed). Candidates not touched since the
# process started are ignored. This keeps two agents in one directory apart, unless they were
# started within the same second (timestamps have second resolution).
agent_pick() {
	local since=$(( $1 - 5 )) born=$(( $1 - 1 )) created mtime path best="" best_c="" newest="" newest_m=0
	while IFS=$'\t' read -r created mtime path; do
		[ -n "$path" ] && [ "${mtime:-0}" -ge "$since" ] || continue
		if [ -n "$created" ] && [ "$created" -ge "$born" ] && { [ -z "$best_c" ] || [ "$created" -lt "$best_c" ]; }; then
			best=$path; best_c=$created
		fi
		if [ "$mtime" -gt "$newest_m" ]; then newest=$path; newest_m=$mtime; fi
	done
	if [ -n "$best" ]; then printf '%s' "$best"; elif [ -n "$newest" ]; then printf '%s' "$newest"; else return 1; fi
}
# agent_epoch ISO-TIMESTAMP: seconds since the epoch, or nothing.
agent_epoch() { [ -n "${1:-}" ] && date -d "$1" +%s 2>/dev/null || true; }
file_mtime() { stat -c %Y "$1" 2>/dev/null || echo 0; }

# agent_emit TOOL RESUME_CMD CWD SESSION_ID HOW: the JSON the resumer contract wants.
agent_emit() {
	jq -cn --arg cmd "$2" --arg cwd "$3" --arg sid "$4" --arg how "$5" --arg tool "$1" \
		'{cmd: $cmd, cwd: $cwd, meta: {tool: $tool, sessionId: $sid, matched_by: $how}}'
}
