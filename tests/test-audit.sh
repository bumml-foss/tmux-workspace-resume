#!/usr/bin/env bash
# scripts/audit.sh on a throwaway repository: an outside contributor's commit with their own
# address and a sign-off passes; an address, a home path or a private host in the content fails,
# and so does one in a commit message.
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

export AUDIT_SKIP_SECRETS=1
repo=$TMP/repo
mkdir -p "$repo/scripts"
cp "$REPO/scripts/audit.sh" "$repo/scripts/"
git -C "$repo" init -q
# commit AUTHOR-EMAIL MESSAGE: commit everything as that author, signed off by them.
commit() {
	git -C "$repo" add -A
	GIT_AUTHOR_NAME="Ann Other" GIT_AUTHOR_EMAIL=$1 GIT_COMMITTER_NAME="Ann Other" GIT_COMMITTER_EMAIL=$1 \
		git -C "$repo" commit -q --allow-empty -m "$2" -m "Signed-off-by: Ann Other <$1>"
}
audit() { "$repo/scripts/audit.sh" 2>&1; }
# The planted values are assembled at run time, so this file passes the audit itself.
mail=$(printf '%s@%s' ann real-mail.test)
home=$(printf '/%s/%s' home ann)
host=$(printf '%s.%s' build lan)

printf 'tmux-workspace-resume restore\n' > "$repo/README.md"
commit "$mail" "Add a README"
has 'audit: clean' audit || fail "an outside author's own address and sign-off must pass: $(audit)"
commit 12345+ann@users.noreply.github.com "Fix a typo"
has 'audit: clean' audit || fail "a GitHub noreply author must pass: $(audit)"

printf 'clone with git clone %s:me/x\n' "$mail" >> "$repo/README.md"
has "$mail" audit || fail "an address in a file must be reported"
git -C "$repo" checkout -q -- README.md

printf 'cd %s/src\n' "$home" > "$repo/notes.txt"
has "$home" audit || fail "a home path in an untracked file must be reported"
printf 'cd /home/me/src\n' > "$repo/notes.txt"
has 'audit: clean' audit || fail "/home/me is the example path: $(audit)"

printf 'ssh %s\n' "$host" >> "$repo/notes.txt"
commit "$mail" "Add notes"
has "$host" audit || fail "a private host in history must be reported"
git -C "$repo" reset -q --hard HEAD~1

GIT_AUTHOR_NAME=me GIT_AUTHOR_EMAIL=me@example.com GIT_COMMITTER_NAME=me GIT_COMMITTER_EMAIL=me@example.com \
	git -C "$repo" commit -q --allow-empty -m "Reported by $mail on the forum"
has "$mail" audit || fail "an address in a commit message body must be reported"
echo ok
