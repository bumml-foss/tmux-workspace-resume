# shellcheck shell=bash
# tmux-workspace-resume — shared helpers (logging, quoting, /proc and tmux access).
# Sourced by bin/tmux-workspace-resume and by the shipped resumers; never executed directly.
# SPDX-License-Identifier: GPL-3.0-or-later

TWR_QUIET=${TWR_QUIET:-0}
quiet_on() { TWR_QUIET=1; }

# ---------------------------------------------------------------- directories
state_dir() { printf '%s' "${XDG_STATE_HOME:-$HOME/.local/state}/tmux-workspace-resume"; }
config_dir() { printf '%s' "${XDG_CONFIG_HOME:-$HOME/.config}/tmux-workspace-resume"; }
log_file() { printf '%s' "$(state_dir)/tmux-workspace-resume.log"; }
state_init() { mkdir -p "$(state_dir)" 2>/dev/null || true; }
# runtime_dir: per-boot scratch (markers, locks). XDG_RUNTIME_DIR is a tmpfs that is cleared on
# reboot, which is exactly the lifetime the "restored for this server" markers need.
runtime_dir() {
	local d
	if [ -n "${XDG_RUNTIME_DIR:-}" ] && [ -d "$XDG_RUNTIME_DIR" ] && [ -w "$XDG_RUNTIME_DIR" ]; then
		d=$XDG_RUNTIME_DIR/tmux-workspace-resume
	else
		d=$(state_dir)/run
	fi
	mkdir -p "$d"
	printf '%s' "$d"
}

# ---------------------------------------------------------------- logging
_log_level_num() {
	case ${1:-info} in
		debug) echo 0 ;; info) echo 1 ;; warn) echo 2 ;; error) echo 3 ;; *) echo 1 ;;
	esac
}
_log() {
	local level=$1; shift
	local want have
	want=$(_log_level_num "${LOG_LEVEL:-info}")
	have=$(_log_level_num "$level")
	[ "$have" -ge "$want" ] || return 0
	local line
	line="$(date '+%Y-%m-%d %H:%M:%S') [$level] $*"
	if [ "$TWR_QUIET" != 1 ] || [ "$level" = error ]; then
		printf '%s\n' "tmux-workspace-resume: $*" >&2
	fi
	if mkdir -p "$(state_dir)" 2>/dev/null; then printf '%s\n' "$line" >> "$(log_file)" 2>/dev/null || true; fi
}
log_debug() { _log debug "$@"; }
log_info() { _log info "$@"; }
log_warn() { _log warn "$@"; }
log_error() { _log error "$@"; }
die() { log_error "$@"; exit 1; }

# ---------------------------------------------------------------- quoting
# shell_quote STRING: single-quote style quoting that every POSIX shell and fish understand.
# (printf %q would emit $'...' for some inputs, which fish cannot parse.)
shell_quote() {
	local s=$1 q="'"
	if [ -n "$s" ] && [[ $s =~ ^[A-Za-z0-9_./:=@%+,-]+$ ]]; then
		printf '%s' "$s"
	else
		printf "%s" "'${s//$q/$q\\$q$q}'"
	fi
}
# argv_to_shell: NUL-separated argv on stdin -> one shell-safe command line on stdout.
argv_to_shell() {
	local arg out="" first=1
	while IFS= read -r -d '' arg; do
		if [ $first -eq 1 ]; then first=0; else out+=" "; fi
		out+=$(shell_quote "$arg")
	done
	printf '%s' "$out"
}
proc_cmdline_to_shell() { argv_to_shell < "/proc/$1/cmdline"; }

# ---------------------------------------------------------------- processes
children_of() { pgrep -P "$1" 2>/dev/null || true; }
proc_comm() { cat "/proc/$1/comm" 2>/dev/null || true; }
# proc_argv0 PID: basename of argv[0] (what tmux shows as #{pane_current_command}).
proc_argv0() {
	local a
	a=$(tr '\0' '\n' < "/proc/$1/cmdline" 2>/dev/null | head -n1) || true
	printf '%s' "${a##*/}"
}
# proc_starttime PID: the kernel start time (clock ticks since boot). Together with the pid it
# identifies a process uniquely; Claude Code stores the same value as "procStart".
proc_starttime() {
	[ -r "/proc/$1/stat" ] || return 1
	sed 's/^.*) //' "/proc/$1/stat" | awk '{print $20}'
}
proc_alive() { [ -d "/proc/$1" ]; }
# proc_ppid PID: parent pid (field after the state, once "pid (comm) " is stripped).
proc_ppid() { sed 's/^.*) //' "/proc/$1/stat" 2>/dev/null | awk '{print $2}'; }
# proc_is_descendant PID ANCESTOR: walk up the parent chain.
proc_is_descendant() {
	local p=$1
	while [ -n "$p" ] && [ "$p" -gt 1 ] 2>/dev/null; do
		[ "$p" = "$2" ] && return 0
		p=$(proc_ppid "$p")
	done
	return 1
}
boot_id() { cat /proc/sys/kernel/random/boot_id 2>/dev/null || echo unknown; }

# ---------------------------------------------------------------- tmux
# tmux_args_init: decide which server to talk to, once. Precedence:
#   TWR_TMUX_SOCKET_NAME (-L, used by the tests) > TMUX_SOCKET config/env (-S) >
#   $TMUX of the calling pane/hook (-S) > tmux's default socket (what byobu uses).
TWR_TMUX_ARGS=()
tmux_args_init() {
	TWR_TMUX_ARGS=()
	if [ -n "${TWR_TMUX_SOCKET_NAME:-}" ]; then
		TWR_TMUX_ARGS=(-L "$TWR_TMUX_SOCKET_NAME")
	elif [ -n "${TMUX_SOCKET:-}" ]; then
		TWR_TMUX_ARGS=(-S "$TMUX_SOCKET")
	elif [ -n "${TMUX:-}" ]; then
		TWR_TMUX_ARGS=(-S "${TMUX%%,*}")
	fi
}
# -u: without a UTF-8 locale (LANG unset, e.g. in a bare systemd or container environment) the
# client asks the server to replace the tabs in format output with "_", which breaks parsing.
tmux_cmd() { command tmux -u "${TWR_TMUX_ARGS[@]}" "$@"; }
has_server() { tmux_cmd list-sessions >/dev/null 2>&1; }
server_pid() { tmux_cmd display -p '#{pid}' 2>/dev/null; }
tmux_version() { tmux_cmd display -p '#{version}' 2>/dev/null || command tmux -V | awk '{print $2}'; }
# pane_idle PANE: the pane's root process (the shell tmux started) has no children, i.e. it sits
# at its prompt. Works for any shell and is false while byobu-shell is still printing its motd.
# Our own process chain does not count (an `tmux-workspace-resume restore` typed into that very pane).
pane_idle() {
	local pid child
	pid=$(tmux_cmd display -p -t "$1" '#{pane_pid}' 2>/dev/null) || return 1
	[ -n "$pid" ] || return 1
	for child in $(children_of "$pid"); do
		proc_is_descendant "$$" "$child" || return 1
	done
	return 0
}
# pane_is_ours PANE: this process runs inside that pane.
pane_is_ours() {
	local pid
	pid=$(tmux_cmd display -p -t "$1" '#{pane_pid}' 2>/dev/null) || return 1
	[ -n "$pid" ] && proc_is_descendant "$$" "$pid"
}
# restore_marker: exists once a restore has completed on the running server (this boot).
restore_marker() { printf '%s/restored-%s-%s' "$(runtime_dir)" "$(boot_id)" "$(server_pid)"; }
restore_attempt_marker() { printf '%s/attempted-%s-%s' "$(runtime_dir)" "$(boot_id)" "$(server_pid)"; }
# The restore lock: held (flock) by a running restore, released by the kernel however it ends.
restore_lock_file() { printf '%s/restore.lock' "$(runtime_dir)"; }
restore_in_progress() { ! flock -n "$(restore_lock_file)" true 2>/dev/null; }
# wait_for_server SECONDS: poll until a server with at least one session answers.
wait_for_server() {
	local n=$(( ${1:-5} * 10 ))
	while ! has_server; do
		n=$((n - 1)); [ "$n" -gt 0 ] || return 1
		sleep 0.1
	done
}
