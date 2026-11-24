# shellcheck shell=bash
# Plan 185: `haseen setup sshd` named its drop-in 90-haseen.conf, but sshd
# keeps the first value it reads for a keyword and reads sshd_config.d/*.conf
# in name order, so any drop-in sorting before it (50-cloud-init.conf with
# `PasswordAuthentication yes`) turned passwords back on. The command now
# writes 01-haseen.conf; this renames the drop-in it wrote before, where it is
# still the file the command wrote, and reloads a running sshd.
# Safe to re-run: without the old file, or with the new one in place, nothing
# is done.

# shellcheck source=../lib/common.sh
source "$HASEEN_PATH/lib/common.sh"

old=/etc/ssh/sshd_config.d/90-haseen.conf
new=/etc/ssh/sshd_config.d/01-haseen.conf

file="$(sysroot_path "$old")"
[[ -f $file && -r $file ]] || exit 0
[[ -e $(sysroot_path "$new") ]] && exit 0
# Only the file the command wrote: its first line names it.
[[ "$(head -n1 -- "$file")" == '# Written by `haseen setup sshd`.' ]] || exit 0

info "renaming $old to $new, so no other sshd drop-in can turn passwords or root login back on"
run_root mv -- "$old" "$new"
# try-: an sshd that does not run stays stopped.
run_root systemctl try-reload-or-restart sshd.service
