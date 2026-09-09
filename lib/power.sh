# shellcheck shell=bash
# ai-revive — shutdown/reboot: the reliable way to power off. Saves first, then hands over to systemd.
# SPDX-License-Identifier: GPL-3.0-or-later

power_action() {
	local action=$1 dry=0
	[ "${2:-}" = "--dry-run" ] && dry=1
	if has_server; then
		save_now --force || die "save failed; not powering off (see $(log_file))"
	else
		log_info "no tmux server running; nothing to save"
	fi
	if [ $dry -eq 1 ]; then echo "would run: systemctl $action"; return 0; fi
	exec systemctl "$action"
}
cmd_shutdown() { power_action poweroff "$@"; }
cmd_reboot() { power_action reboot "$@"; }
