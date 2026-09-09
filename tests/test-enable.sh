#!/usr/bin/env bash
# enable/disable: one marker block in the byobu (or tmux) config, idempotent, removable, and never
# containing the two option names byobu greps for. systemd is not touched (AI_REVIVE_NO_SYSTEMD=1).
. "$(dirname "${BASH_SOURCE[0]}")/lib/harness.sh"

export BYOBU_CONFIG_DIR=$TMP/byobu
mkdir -p "$BYOBU_CONFIG_DIR"
printf '# user line kept\nset -g mouse on' > "$BYOBU_CONFIG_DIR/.tmux.conf"   # no trailing newline on purpose

"$AR" enable --byobu
conf=$BYOBU_CONFIG_DIR/.tmux.conf
grep -qx '# >>> ai-revive >>>' "$conf" || fail "block begin missing"
grep -qx '# <<< ai-revive <<<' "$conf" || fail "block end missing"
grep -qF "run-shell -b \"$REPO/ai-revive.tmux\"" "$conf" || fail "run-shell line missing: $(cat "$conf")"
grep -q '^set -g mouse on$' "$conf" || fail "existing content damaged: $(cat "$conf")"
grep -qE 'default-(command|shell)' "$conf" && fail "byobu trigger string written"
"$AR" enable --byobu
assert_eq "$(grep -c '>>> ai-revive' "$conf")" 1 "enable is idempotent"
assert_eq "$(wc -l < "$conf")" 5 "line count after double enable"

# byobu flavour is the default when BYOBU_CONFIG_DIR is set and byobu-ai-revive is used
has "enabled in:    $conf" "$REPO/bin/byobu-ai-revive" status || fail "status does not report the byobu file"

# a block pointing at another install location gets replaced, not duplicated
sed -i "s|$REPO/ai-revive.tmux|/usr/share/ai-revive/ai-revive.tmux|" "$conf"
"$AR" enable --byobu
assert_eq "$(grep -c 'ai-revive.tmux' "$conf")" 1 "old block replaced"
grep -qF "$REPO/ai-revive.tmux" "$conf" || fail "new path not written"

"$AR" disable
grep -q 'ai-revive' "$conf" && fail "disable left traces: $(cat "$conf")"
grep -q '^set -g mouse on$' "$conf" || fail "disable damaged user content"

# --tmux flavour writes ~/.tmux.conf and a running server gets the hooks immediately
fresh_server s
"$AR" enable --tmux
grep -qF "run-shell -b \"$REPO/ai-revive.tmux\"" "$HOME/.tmux.conf" || fail "$HOME/.tmux.conf block missing"
wait_until 5 '[ "$(T show-hooks -g | grep -c "\[900\]")" = 10 ]' || fail "hooks not installed on the running server"
"$AR" disable
assert_eq "$(T show-hooks -g | grep -c '\[900\]')" 0 "hooks removed by disable"
[ ! -e "$XDG_CONFIG_HOME/systemd" ] || fail "systemd must not be touched in tests"
echo ok
