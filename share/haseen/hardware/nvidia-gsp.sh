# shellcheck shell=bash
# nvidia-gsp — early KMS for an NVIDIA GPU with GSP firmware (Turing or newer),
# which is what the open kernel module needs to drive the console and Hyprland
# from the first frame.
#
# Adapted from Omarchy install/hardware/nvidia.sh (MIT, Copyright (c) David
# Heinemeier Hansson). Only the initramfs half lives here: layers/desktop
# already writes `options nvidia_drm modeset=1` and the session environment, and
# never touches mkinitcpio.

conf=/etc/mkinitcpio.conf.d/haseen-nvidia.conf

if [[ -e $(sysroot_path "$conf") ]]; then
    info "hw nvidia-gsp: $conf already exists"
    return 0
fi
if [[ ! -d $(sysroot_path /etc/mkinitcpio.conf.d) && ! -f $(sysroot_path /etc/mkinitcpio.conf) ]]; then
    info "hw nvidia-gsp: mkinitcpio is not in use; nothing to do"
    return 0
fi

# The quirk matches the PCI id alone, and on Arch haseen installs no driver
# (layers/desktop only warns), so the modules can be missing when this runs.
# The trailing `?` marks each one optional to mkinitcpio: without it every
# initramfs build, the kernel-upgrade hook's included, fails with "module not
# found" until a driver is installed, and the ledger never revisits the quirk.
# With it the file is inert until nvidia-open (or another driver) arrives, and
# early KMS starts with the next build after that. mkinitcpio sources the file
# as bash, so each name is quoted to keep `?` from globbing (plan 189).
write_root_file "$conf" <<'EOF'
# Written by `haseen hw apply` (quirk: nvidia-gsp).
MODULES+=('nvidia?' 'nvidia_modeset?' 'nvidia_uvm?' 'nvidia_drm?')
EOF
# Without a driver the file is inert, so say that rather than send the owner
# off to rebuild an initramfs that would change nothing.
warn "hw nvidia-gsp: wrote $conf; early KMS takes effect after a driver such as nvidia-open is installed, the initramfs is rebuilt ('sudo mkinitcpio -P') and the machine reboots"
