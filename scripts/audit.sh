#!/usr/bin/env bash
# Privacy audit before anything is published: fails when the git history (metadata, message and
# every added or removed line of every commit), uncommitted changes or untracked files contain
# data that must not become public.
#
#   secrets      gitleaks over the whole history (local binary, else its docker image; skipped
#                with a warning when neither is available)
#   e-mail       addresses other than the project's own (AUDIT_ALLOWED_EMAILS, an extended regex)
#   paths/hosts  home directories other than /home/me, private IPv4 addresses and
#                .local/.lan/.internal/.home.arpa host names
#   session ids  UUIDs of real agent sessions on this machine (~/.claude, ~/.codex, ~/.gemini,
#                ~/.copilot), also as shortened "xxxxxxxx-..." examples
#   denylist     optional private patterns, one case-insensitive extended regex per line, read from
#                ${AI_REVIVE_AUDIT_DENYLIST:-$XDG_CONFIG_HOME/ai-revive/audit-denylist}. Keep that
#                file outside the repository: committing it would publish what it protects.
#
# Usage: scripts/audit.sh (or `make audit`). Exit 0 when clean, 1 on findings.
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail
export LC_ALL=C
cd "$(dirname "${BASH_SOURCE[0]}")/.."

AUDIT_ALLOWED_EMAILS=${AUDIT_ALLOWED_EMAILS:-'bumml\.foss@proton\.me|noreply@anthropic\.com|[^@]+@example\.(com|org|net)'}
UUID='[0-9a-fA-F]{8}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{4}-[0-9a-fA-F]{12}'
findings=0
tmp=$(mktemp -d)
trap 'rm -rf "$tmp"' EXIT

# finding TITLE [DETAILS]: report one problem (details indented, at most 20 lines).
finding() {
	printf 'audit: %s\n' "$1" >&2
	if [ -n "${2:-}" ]; then printf '%s\n' "$2" | head -20 | sed 's/^/    /' >&2; fi
	findings=$((findings + 1))
}

# Everything that would be published.
{
	git log --all -p --no-color --format='commit %H%nAuthor: %an <%ae>%nCommitter: %cn <%ce>%n%n%B'
	git diff --no-color HEAD
	git ls-files -z --others --exclude-standard | xargs -0r cat --
} > "$tmp/all"

# secrets
if command -v gitleaks >/dev/null 2>&1; then
	gitleaks detect --source . --log-opts=--all --no-banner --redact > "$tmp/gitleaks" 2>&1 ||
		finding "gitleaks reports secrets" "$(cat "$tmp/gitleaks")"
elif command -v docker >/dev/null 2>&1; then
	docker run --rm --user "$(id -u):$(id -g)" -v "$PWD:/repo:ro" zricethezav/gitleaks:latest \
		detect --source /repo --log-opts=--all --no-banner --redact > "$tmp/gitleaks" 2>&1 ||
		finding "gitleaks reports secrets" "$(cat "$tmp/gitleaks")"
else
	echo "audit: neither gitleaks nor docker is available; secret scan skipped" >&2
fi

# e-mail addresses
grep -ohE '[A-Za-z0-9._%+-]+@[A-Za-z0-9-]+(\.[A-Za-z0-9-]+)*\.[A-Za-z]{2,}' "$tmp/all" | sort -u |
	grep -vixE "$AUDIT_ALLOWED_EMAILS" > "$tmp/emails" || true
if [ -s "$tmp/emails" ]; then finding "e-mail addresses other than the project's" "$(cat "$tmp/emails")"; fi

# home directories, private addresses and host names
grep -oE '/home/[A-Za-z0-9_.-]+' "$tmp/all" | sort -u | grep -vxF /home/me > "$tmp/homes" || true
if [ -s "$tmp/homes" ]; then finding "home directories (examples use /home/me)" "$(cat "$tmp/homes")"; fi
grep -oE '(^|[^0-9.])(10(\.[0-9]{1,3}){3}|192\.168(\.[0-9]{1,3}){2}|172\.(1[6-9]|2[0-9]|3[01])(\.[0-9]{1,3}){2})([^0-9.]|$)' \
	"$tmp/all" | sort -u > "$tmp/ips" || true
if [ -s "$tmp/ips" ]; then finding "private IPv4 addresses" "$(cat "$tmp/ips")"; fi
grep -oiE '[A-Za-z0-9][A-Za-z0-9-]*\.(local|lan|internal|home\.arpa)([^A-Za-z0-9.-]|$)' "$tmp/all" | sort -u > "$tmp/hosts" || true
if [ -s "$tmp/hosts" ]; then finding "private host names" "$(cat "$tmp/hosts")"; fi

# ids of real agent sessions on this machine
dirs=()
for d in "$HOME/.claude" "$HOME/.codex" "$HOME/.gemini" "$HOME/.copilot"; do
	if [ -d "$d" ]; then dirs+=("$d"); fi
done
if [ ${#dirs[@]} -gt 0 ]; then
	{ find "${dirs[@]}" -maxdepth 6 2>/dev/null; cat "$HOME"/.claude/sessions/*.json 2>/dev/null; } |
		grep -oE "$UUID" | tr 'A-F' 'a-f' | sort -u > "$tmp/real-ids" || true
	grep -oE "$UUID" "$tmp/all" | tr 'A-F' 'a-f' | sort -u > "$tmp/repo-ids" || true
	comm -12 "$tmp/real-ids" "$tmp/repo-ids" > "$tmp/leaked-ids"
	grep -oE '[0-9a-f]{8}-\.\.\.' "$tmp/all" | cut -c1-8 | sort -u | while read -r prefix; do
		grep -m1 "^$prefix" "$tmp/real-ids" || true
	done >> "$tmp/leaked-ids"
	if [ -s "$tmp/leaked-ids" ]; then finding "ids of real agent sessions on this machine (use made-up ids)" "$(sort -u "$tmp/leaked-ids")"; fi
fi

# private denylist
deny=${AI_REVIVE_AUDIT_DENYLIST:-${XDG_CONFIG_HOME:-$HOME/.config}/ai-revive/audit-denylist}
if [ -r "$deny" ]; then
	while IFS= read -r re || [ -n "$re" ]; do
		case $re in ''|'#'*) continue ;; esac
		hits=$(grep -iE -- "$re" "$tmp/all" | sort -u | cut -c1-160) || true
		if [ -n "$hits" ]; then finding "private pattern /$re/ (from $deny)" "$hits"; fi
	done < "$deny"
else
	echo "audit: no private denylist at $deny (optional)" >&2
fi

if [ "$findings" -gt 0 ]; then
	echo "audit: $findings finding(s): do not push this history to a public remote" >&2
	exit 1
fi
echo "audit: clean ($(git rev-list --all --count) commits, uncommitted changes and untracked files)"
