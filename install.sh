#!/usr/bin/env bash
# install.sh — put haseen on an existing CachyOS (or Arch) install.
#
# 1. Preflight: refuse NixOS (use the flake) and unknown distros.
# 2. Install the tree: bin/ -> PREFIX/bin, share/haseen -> PREFIX/share/haseen,
#    systemd user units -> PREFIX/lib/systemd/user. PREFIX defaults to
#    /usr/local because these files are not owned by a package (yet; see
#    plans/README.md, PKGBUILD phase).
# 3. Apply the default layers through the installed `haseen layer apply`.
#
# Everything privileged goes through the common.sh helpers; --dry-run prints
# the full plan and changes nothing.
set -Eeuo pipefail

REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
export HASEEN_PATH="$REPO/share/haseen"
# shellcheck source=share/haseen/lib/preflight.sh
source "$HASEEN_PATH/lib/preflight.sh"

DEFAULT_LAYERS=(base chaotic desktop theme shell)
PREFIX=/usr/local
LAYERS=()
TREE_ONLY=false
UNINSTALL=false

usage() {
    cat <<EOF
Usage: ./install.sh [--dry-run] [--yes] [--prefix DIR] [--layers a,b,c]
                    [--tree-only] [--uninstall-tree]

  --layers      layers to apply (default: ${DEFAULT_LAYERS[*]})
                optional: secureboot ai dms gaming flatpak (haseen layer list)
  --tree-only   install bin/ and share/ only, apply no layers
  --uninstall-tree
                remove PREFIX/bin/haseen*, PREFIX/share/haseen and the user
                units; applied layers stay (remove them first with
                haseen layer remove)
EOF
}

while (($# > 0)); do
    case "$1" in
    --dry-run) DRY_RUN=true ;;
    --yes | -y) ASSUME_YES=true ;;
    --prefix) PREFIX="${2:?--prefix needs a directory}"; shift ;;
    --layers) IFS=, read -r -a LAYERS <<<"${2:?--layers needs a list}"; shift ;;
    --tree-only) TREE_ONLY=true ;;
    --uninstall-tree) UNINSTALL=true ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
    esac
    shift
done
((${#LAYERS[@]} > 0)) || LAYERS=("${DEFAULT_LAYERS[@]}")
require_not_root

UNIT_DIR="$PREFIX/lib/systemd/user"

uninstall_tree() {
    local f
    for f in "$REPO"/bin/haseen*; do
        run_root rm -f "$PREFIX/bin/${f##*/}"
    done
    for f in "$REPO"/share/haseen/systemd/user/*; do
        [[ -e $f ]] && run_root rm -f "$UNIT_DIR/${f##*/}"
    done
    run_root rm -rf "$PREFIX/share/haseen"
    info "haseen tree removed from $PREFIX"
}

install_tree() {
    local f
    # Replace share/haseen atomically: copy beside, then swap.
    run_root rm -rf "$PREFIX/share/haseen.new" "$PREFIX/share/haseen.old"
    run_root install -d -m 0755 "$PREFIX/share"
    run_root cp -a "$REPO/share/haseen" "$PREFIX/share/haseen.new"
    if [[ -d $PREFIX/share/haseen ]]; then
        run_root mv "$PREFIX/share/haseen" "$PREFIX/share/haseen.old"
    fi
    run_root mv "$PREFIX/share/haseen.new" "$PREFIX/share/haseen"
    run_root rm -rf "$PREFIX/share/haseen.old"
    for f in "$REPO"/bin/haseen*; do
        install_root_file "$f" "$PREFIX/bin/${f##*/}" 0755
    done
    for f in "$REPO"/share/haseen/systemd/user/*; do
        [[ -e $f ]] && install_root_file "$f" "$UNIT_DIR/${f##*/}" 0644
    done
    info "haseen $(cat "$REPO/share/haseen/VERSION") installed under $PREFIX"
}

preflight_all
preflight_report | sed 's/^/    /'
case "$HASEEN_DISTRO" in
cachyos | arch) ;;
omarchy)
    warn "this is an Omarchy host. haseen replaces Omarchy rather than layering on it;"
    warn "read docs/decisions/0001-haseen-replaces-omarchy.md before continuing."
    confirm "Continue on an Omarchy host?" || exit 1
    ;;
nixos) die "NixOS is configured through the flake (nix/README.md), not this installer." ;;
*) die "unsupported distro '${DISTRO_PRETTY:-unknown}'. haseen targets CachyOS, Arch and NixOS." ;;
esac

if $UNINSTALL; then
    confirm "Remove the haseen tree from $PREFIX?" || exit 1
    uninstall_tree
    exit 0
fi

confirm "Install haseen into $PREFIX and apply: ${LAYERS[*]}?" || exit 1
install_tree
$TREE_ONLY && exit 0

# Under --dry-run nothing was copied, so plan the layers from the checkout.
haseen_bin="$PREFIX/bin/haseen"
$DRY_RUN && haseen_bin="$REPO/bin/haseen"
flags=()
$DRY_RUN && flags+=(--dry-run)
$ASSUME_YES && flags+=(--yes)
HASEEN_PATH="$(dirname "$haseen_bin")/../share/haseen" "$haseen_bin" layer apply "${LAYERS[@]}" "${flags[@]}"
