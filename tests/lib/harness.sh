#!/usr/bin/env bash
# Sourced by every tests/test-*.sh. Gives each test a throwaway HOME/XDG tree, a private tmux
# server (socket name ai-revive-test-<pid>) and fake `claude` / `ssh` executables on PATH.
# Nothing here ever talks to the developer's own tmux/byobu server or to systemd.
set -euo pipefail

REPO=$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)
AR=$REPO/bin/ai-revive
export REPO AR

for tool in tmux jq flock setsid; do
	command -v "$tool" >/dev/null 2>&1 || { echo "SKIP: $tool not installed"; exit 0; }
done

TMP=$(mktemp -d)
export TMP
export HOME=$TMP/home XDG_CONFIG_HOME=$TMP/config XDG_STATE_HOME=$TMP/state XDG_RUNTIME_DIR=$TMP/run
mkdir -p "$HOME" "$XDG_CONFIG_HOME" "$XDG_STATE_HOME" "$XDG_RUNTIME_DIR"
# The developer may run the suite from inside byobu: never let that leak into the test server.
unset TMUX TMUX_PANE BYOBU_CONFIG_DIR AI_REVIVE_HOME
export AI_REVIVE_TMUX_SOCKET_NAME=ai-revive-test-$$
export AI_REVIVE_NO_SYSTEMD=1
export AI_REVIVE_RESTORE_SETTLE_S=0
export AI_REVIVE_RESTORE_DELAY_MS=50
export AI_REVIVE_RESTORE_STAGGER_MS=0
export AI_REVIVE_LOG_LEVEL=debug

export FAKE_LOG=$TMP/fakelog
mkdir -p "$FAKE_LOG" "$TMP/bin"
cp "$REPO"/tests/fakes/* "$TMP/bin/"
chmod +x "$TMP"/bin/*
ln -s "$(command -v tail)" "$TMP/bin/ssh"
export PATH=$TMP/bin:$PATH
# tmux starts login shells; Debian's /etc/profile resets PATH, so the temp HOME re-adds the fakes.
printf 'export PATH=%s:$PATH\n' "$TMP/bin" > "$HOME/.profile"
cp "$HOME/.profile" "$HOME/.bashrc"

# T: tmux against the private server.
T() { tmux -L "$AI_REVIVE_TMUX_SOCKET_NAME" -f /dev/null "$@"; }

cleanup() {
	local rc=$? n=20
	T kill-server 2>/dev/null || true
	# pane processes (fake claude/ssh) die asynchronously and may still be writing into $TMP
	while [ "$n" -gt 0 ] && ! rm -rf "$TMP" 2>/dev/null; do sleep 0.1; n=$((n - 1)); done
	rm -rf "$TMP" 2>/dev/null || true
	exit "$rc"
}
trap cleanup EXIT

fail() { echo "FAIL: $*" >&2; exit 1; }
assert_eq() { [ "$1" = "$2" ] || fail "${3:-assert_eq}: expected '$2', got '$1'"; }
# assert_json FILE FILTER [MSG]: on failure the document is printed too, so CI logs show why.
assert_json() {
	jq -e "$2" "$1" >/dev/null 2>&1 && return 0
	{ jq -c . "$1" 2>/dev/null || cat "$1"; } | head -c 6000 >&2 || true
	echo >&2
	fail "${3:-assert_json}: '$2' does not hold in $1"
}
# wait_until <seconds> '<condition>': poll every 0.1 s until the condition (eval'd each time) holds.
wait_until() {
	local n=$(( $1 * 10 )) cond=$2
	while ! eval "$cond" >/dev/null 2>&1; do
		n=$((n - 1)); [ "$n" -gt 0 ] || return 1
		sleep 0.1
	done
}
pane_cmd() { T display -p -t "$1" '#{pane_current_command}'; }
snapshot_dir() { printf '%s' "$XDG_STATE_HOME/ai-revive/snapshots"; }
last_snapshot() { readlink -f "$(snapshot_dir)/last.json"; }
# fresh_server [NAME [COLS ROWS]]: start a detached session (default 200x50; 80x24 is too small for splits).
fresh_server() {
	local n=10
	until T new-session -d -s "${1:-0}" -x "${2:-200}" -y "${3:-50}" -c "$HOME" 2>/dev/null; do
		n=$((n - 1)); [ "$n" -gt 0 ] || fail "could not start the test tmux server"
		sleep 0.2
	done
}
# kill_server: kill-server and wait until the socket is really gone (a client connecting to a
# dying server sees "server exited unexpectedly").
kill_server() {
	T kill-server 2>/dev/null || true
	local n=30
	while T list-sessions >/dev/null 2>&1 && [ "$n" -gt 0 ]; do sleep 0.1; n=$((n - 1)); done
	sleep 0.2
}
# layout_shape LAYOUT: strip the checksum and the pane ids so two layouts compare by geometry.
layout_shape() { printf '%s' "$1" | sed -E 's/^[0-9a-f]{4},//; s/([0-9]+x[0-9]+,[0-9]+,[0-9]+),[0-9]+/\1,P/g'; }
# has PATTERN CMD...: run CMD, capture its output, grep for PATTERN (avoids SIGPIPE under pipefail).
has() { local pat=$1 out; shift; out=$("$@" 2>&1) || true; grep -q -- "$pat" <<< "$out"; }
# type_in PANE COMMAND: wait until the pane runs a shell, then type COMMAND + Enter.
type_in() {
	local pane=$1 cmd=$2
	wait_until 10 '[ "$(pane_cmd "$pane")" = bash ] || [ "$(pane_cmd "$pane")" = sh ] || [ "$(pane_cmd "$pane")" = zsh ]' || fail "no shell in pane $pane"
	sleep 0.2
	T send-keys -t "$pane" -l -- "$cmd"
	T send-keys -t "$pane" Enter
}
