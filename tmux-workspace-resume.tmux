#!/usr/bin/env bash
# tmux-workspace-resume — tmux plugin entry point. Run once per server start, either by TPM
# (set -g @plugin 'bumml-foss/tmux-workspace-resume') or from byobu's ~/.config/byobu/.tmux.conf via
# `run-shell -b "/usr/share/tmux-workspace-resume/tmux-workspace-resume.tmux"` (what `tmux-workspace-resume enable` writes).
#
# It installs the save hooks and key bindings on the running server and starts the automatic
# restore in the background. Everything is detached from tmux's run-shell so the config load
# never blocks on it.
# SPDX-License-Identifier: GPL-3.0-or-later
set -euo pipefail

here=$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")
if [ -x "$here/bin/tmux-workspace-resume" ]; then
	bin=$here/bin/tmux-workspace-resume                       # checkout or TPM clone
elif [ -x "$here/../../bin/tmux-workspace-resume" ]; then
	bin=$(readlink -f "$here/../../bin/tmux-workspace-resume") # /usr/share/tmux-workspace-resume -> /usr/bin/tmux-workspace-resume
else
	bin=$(command -v tmux-workspace-resume) || { echo "tmux-workspace-resume.tmux: cannot find the tmux-workspace-resume executable" >&2; exit 1; }
fi
export TWR_HOME=$here

"$bin" -q hook install
setsid -f "$bin" -q restore --auto </dev/null >/dev/null 2>&1 || true
