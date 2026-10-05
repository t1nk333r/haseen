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

write_root_file "$conf" <<'EOF'
# Written by `haseen hw apply` (quirk: nvidia-gsp).
MODULES+=(nvidia nvidia_modeset nvidia_uvm nvidia_drm)
EOF
warn "hw nvidia-gsp: wrote $conf; rebuild the initramfs ('sudo mkinitcpio -P') and reboot"
