# shellcheck shell=bash
# ai-revive — configuration. Precedence: built-in defaults < $XDG_CONFIG_HOME/ai-revive/config
# (plain KEY=VALUE, sourced by bash) < environment AI_REVIVE_<KEY>. Every key is exported as
# AI_REVIVE_<KEY> so resumers see the effective values. See examples/config.
# SPDX-License-Identifier: GPL-3.0-or-later
# shellcheck disable=SC2034  # the keys are read by the other lib files

AI_REVIVE_CONFIG_KEYS="AUTO_RESTORE SAVE_INTERVAL_MIN SAVE_DEBOUNCE_S RESTORE_SETTLE_S KEEP_SNAPSHOTS \
RESUME_COMMANDS RESTORE_DELAY_MS RESTORE_STAGGER_MS SHELL_WAIT_S KEY_SAVE KEY_RESTORE TMUX_SOCKET LOG_LEVEL"

config_load() {
	AUTO_RESTORE=reboot          # always | reboot | never
	SAVE_INTERVAL_MIN=5          # systemd user timer period
	SAVE_DEBOUNCE_S=3            # coalesce hook-triggered saves
	RESTORE_SETTLE_S=15          # re-save this long after a restore (0 = never)
	KEEP_SNAPSHOTS=20
	RESUME_COMMANDS="vi vim nvim emacs nano man less more tail top htop"
	RESTORE_DELAY_MS=300         # after the pane's shell is up, before typing the command
	RESTORE_STAGGER_MS=300       # between panes, so ten agents do not start in the same instant
	SHELL_WAIT_S=10              # how long to wait for a restored pane's shell
	KEY_SAVE=C-s                 # prefix + KEY_SAVE saves
	KEY_RESTORE=C-r              # prefix + KEY_RESTORE restores last.json
	TMUX_SOCKET=                 # -S path for non-default sockets (TMUX_TMPDIR users)
	LOG_LEVEL=info               # debug | info | warn | error

	local f=${AI_REVIVE_CONFIG_FILE:-$(config_dir)/config}
	if [ -r "$f" ]; then
		# shellcheck source=/dev/null
		. "$f"
	fi

	local key envname
	for key in $AI_REVIVE_CONFIG_KEYS; do
		envname=AI_REVIVE_$key
		if [ -n "${!envname+x}" ]; then
			printf -v "$key" '%s' "${!envname}"
		fi
		export "$envname=${!key}"
	done
}
