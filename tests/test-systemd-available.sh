#!/usr/bin/env bash
# systemd_available: a degraded user manager still counts; offline or missing does not. Uses a
# fake systemctl, never the real one.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"
. "$REPO/lib/common.sh"
. "$REPO/lib/enable.sh"

cat > "$TMP/bin/systemctl" <<'EOF'
#!/usr/bin/env bash
# is-system-running prints the state and exits 0 only for "running"
[ "$*" = "--user is-system-running" ] || exit 2
echo "$FAKE_SYSTEMD_STATE"
[ "$FAKE_SYSTEMD_STATE" = running ]
EOF
chmod +x "$TMP/bin/systemctl"

unset TWR_NO_SYSTEMD
for state in running degraded starting; do
	FAKE_SYSTEMD_STATE=$state systemd_available || fail "state '$state' must count as available"
done
for state in offline stopping maintenance; do
	if FAKE_SYSTEMD_STATE=$state systemd_available; then fail "state '$state' must not count as available"; fi
done
if TWR_NO_SYSTEMD=1 FAKE_SYSTEMD_STATE=running systemd_available; then fail "TWR_NO_SYSTEMD=1 must win"; fi
echo ok
