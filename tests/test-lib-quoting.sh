#!/usr/bin/env bash
# shell_quote / argv_to_shell round-trip through eval for awkward arguments.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
. "$REPO/lib/common.sh"

check() {
	local quoted; quoted=$(printf '%s\0' "$@" | argv_to_shell)
	eval "set -- $quoted"
	local got; got=$(printf '%s\n' "$@")
	local want; want=$(printf '%s\n' "${ORIG[@]}")
	assert_eq "$got" "$want" "round-trip of: $quoted"
}
ORIG=(ssh -p 2222 user@host); check "${ORIG[@]}"
ORIG=(vim "file with spaces.txt" "it's" 'say "hi"' '$HOME' '%h' 'a;b' '*.c' ''); check "${ORIG[@]}"
ORIG=(claude --resume 12345678-90ab-4cde-8f01-234567890abc); check "${ORIG[@]}"
assert_eq "$(shell_quote plain/path:x=1)" "plain/path:x=1" "bare token stays bare"
assert_eq "$(shell_quote "it's")" "'it'\\''s'" "single quote escaping"
assert_eq "$(shell_quote '')" "''" "empty string"
echo ok
