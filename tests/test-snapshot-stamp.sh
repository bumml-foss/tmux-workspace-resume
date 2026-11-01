#!/usr/bin/env bash
# snapshot_stamp: well-formed and never going backwards across a second boundary (the Rust
# coreutils date does, which made names sort out of order).
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
. "$REPO/lib/common.sh"
. "$REPO/lib/snapshot.sh"

prev=""
for _ in $(seq 1 2000); do
	s=$(snapshot_stamp)
	[[ $s =~ ^[0-9]{8}T[0-9]{6}\.[0-9]{3}$ ]] || fail "malformed stamp: $s"
	if [ -n "$prev" ] && [[ $s < $prev ]]; then fail "stamps went backwards: $prev -> $s"; fi
	prev=$s
done
echo ok
