# shellcheck shell=bash
# Plan 107: Omasnap replaces Tensaku as haseen's screenshot tool (owner,
# 2026-10-21). The desktop layer installs it on a new machine; this installs
# it where the desktop layer was applied before, from Omarchy's [omarchy]
# repo only, as the layer does (pkg_install_omarchy, the omarchy: entry in
# layers/desktop/packages.txt). Without that repo it is skipped with a warning
# that names `haseen layer apply omarchy-repo desktop`, and haseen's capture
# keeps slurp, grim and an installed Tensaku or swappy.
#
# Tensaku stays installed: it is a package the user has, and removing it is
# the user's call (plans/107-omasnap.md, Owner steps). Safe to re-run: an
# installed Omasnap, or a machine without the desktop layer, is left alone.

# shellcheck source=../lib/layers.sh
source "$HASEEN_PATH/lib/layers.sh"

layer_is_applied desktop || exit 0
# The skip warning names the layer to apply again.
LAYER_NAME=desktop
pkg_install_omarchy omasnap
