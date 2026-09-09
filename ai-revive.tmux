#!/usr/bin/env bash
# ai-revive — tmux plugin entry point. Run once per server start, either by TPM
# (set -g @plugin 'bumml/ai-revive') or from byobu's ~/.config/byobu/.tmux.conf via
# `run-shell -b "/usr/share/ai-revive/ai-revive.tmux"` (what `ai-revive enable` writes).
#
# It installs the save hooks and key bindings on the running server and starts the automatic
# restore in the background. Everything is detached from tmux's run-shell so the config load
# never blocks on it.
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

here=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
if [ -x "$here/bin/ai-revive" ]; then
	bin=$here/bin/ai-revive                       # checkout or TPM clone
elif [ -x "$here/../../bin/ai-revive" ]; then
	bin=$(readlink -f "$here/../../bin/ai-revive") # /usr/share/ai-revive -> /usr/bin/ai-revive
else
	bin=$(command -v ai-revive) || { echo "ai-revive.tmux: cannot find the ai-revive executable" >&2; exit 1; }
fi
export AI_REVIVE_HOME=$here

"$bin" -q hook install
setsid -f "$bin" -q restore --auto </dev/null >/dev/null 2>&1 || true
