#!/usr/bin/env bash
# Privacy audit before anything is published: fails when the history of HEAD (every commit
# message and every added or removed line), uncommitted changes or untracked files contain data
# that must not become public. It checks the repository's content, the same for everyone;
# commit authors and identity trailers are public by design and are not checked.
#
#   secrets      gitleaks over the history of HEAD (local binary, else its docker image; skipped
#                with a warning when neither is available, or with AUDIT_SKIP_SECRETS=1)
#   e-mail       addresses in files and commit messages other than the allowed ones
#                (AUDIT_ALLOWED_EMAILS, an extended regex: the project's, @example.com/.org/.net
#                and GitHub's noreply addresses); author, committer and trailer lines such as
#                Signed-off-by are left out
#   paths/hosts  home directories other than /home/me, private IPv4 addresses and
#                .local/.lan/.internal/.home.arpa host names
#
# Usage: scripts/audit.sh (or `make audit`). Exit 0 when clean, 1 on findings.
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
export LC_ALL=C
cd "$(dirname "${BASH_SOURCE[0]}")/.."

AUDIT_ALLOWED_EMAILS=${AUDIT_ALLOWED_EMAILS:-'bumml\.foss@proton\.me|noreply@anthropic\.com|[^@]+@example\.(com|org|net)|[0-9]+\+[^@]+@users\.noreply\.github\.com'}
TRAILERS='(signed-off|co-authored|reviewed|acked|tested|reported|suggested|helped|assisted)-by'
findings=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# finding TITLE [DETAILS]: report one problem (details indented, at most 20 lines).
finding() {
	printf 'audit: %s\n' "$1" >&2
	if [ -n "${2:-}" ]; then printf '%s\n' "$2" | head -20 | sed 's/^/    /' >&2; fi
	findings=$((findings + 1))
}

# Everything that would be published, without the identity lines: commit messages and diffs of
# HEAD's history (trailers dropped; diff lines start with +, - or a space, so they stay),
# uncommitted changes and untracked files.
{
	git log -p --no-color --format='commit %H%n%n%B' HEAD | grep -viE "^$TRAILERS:" || true
	git diff --no-color HEAD
	git ls-files -z --others --exclude-standard | xargs -0r cat --
} > "$tmp/all"

# secrets
if [ "${AUDIT_SKIP_SECRETS:-0}" = 1 ]; then
	echo "audit: secret scan skipped (AUDIT_SKIP_SECRETS=1)" >&2
elif command -v gitleaks >/dev/null 2>&1; then
	gitleaks detect --source . --log-opts=HEAD --no-banner --redact > "$tmp/gitleaks" 2>&1 ||
		finding "gitleaks reports secrets" "$(cat "$tmp/gitleaks")"
elif command -v docker >/dev/null 2>&1; then
	docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/repo:ro" zricethezav/gitleaks:latest \
		detect --source /repo --log-opts=HEAD --no-banner --redact > "$tmp/gitleaks" 2>&1 ||
		finding "gitleaks reports secrets" "$(cat "$tmp/gitleaks")"
else
	echo "audit: neither gitleaks nor docker is available; secret scan skipped" >&2
fi

# e-mail addresses
grep -ohE '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}' "$tmp/all" | sort -u |
	grep -vixE "$AUDIT_ALLOWED_EMAILS" > "$tmp/emails" || true
if [ -s "$tmp/emails" ]; then finding "e-mail addresses in files or commit messages (examples use @example.com)" "$(cat "$tmp/emails")"; fi

# home directories, private addresses and host names
grep -oE '/home/[A-Za-z0-9_.-]+' "$tmp/all" | sort -u | grep -vxF /home/me > "$tmp/homes" || true
if [ -s "$tmp/homes" ]; then finding "home directories (examples use /home/me)" "$(cat "$tmp/homes")"; fi
grep -oE '(^|[^0-9.])(10(\.[0-9]{1,3}){3}|192\.168(\.[0-9]{1,3}){2}|172\.(1[6-9]|2[0-9]|3[01])(\.[0-9]{1,3}){2})([^0-9.]|$)' \
	"$tmp/all" | sort -u > "$tmp/ips" || true
if [ -s "$tmp/ips" ]; then finding "private IPv4 addresses" "$(cat "$tmp/ips")"; fi
grep -oiE '[A-Za-z0-9][A-Za-z0-9-]*\.(local|lan|internal|home\.arpa)([^A-Za-z0-9.-]|$)' "$tmp/all" | sort -u > "$tmp/hosts" || true
if [ -s "$tmp/hosts" ]; then finding "private host names" "$(cat "$tmp/hosts")"; fi

if [ "$findings" -gt 0 ]; then
	echo "audit: $findings finding(s): do not publish this history" >&2
	exit 1
fi
echo "audit: clean ($(git rev-list --count HEAD) commits, uncommitted changes and untracked files)"
