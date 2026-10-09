#!/usr/bin/env bash
# CLI basics: version, help, list without snapshots, unknown command, quiet flag.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

assert_eq "$("$AR" version)" "$(cat "$REPO/VERSION")" "version"
has '^usage: tmux-workspace-resume' "$AR" help || fail "help"
has 'no snapshots yet' "$AR" list || fail "list without snapshots"
"$AR" bogus >/dev/null 2>&1 && fail "unknown command must fail"
rc=0; "$AR" restore >/dev/null 2>&1 || rc=$?
[ "$rc" -ne 0 ] || fail "restore without snapshot must fail"
"$AR" -q save                                  # no server: silent no-op
[ ! -e "$(snapshot_dir)/last.json" ] || fail "save without server wrote a snapshot"
fresh_server s
out=$("$AR" -q save 2>&1); assert_eq "$out" "" "quiet save prints nothing"
[ -e "$(snapshot_dir)/last.json" ] || fail "quiet save wrote nothing"
echo ok
