#!/usr/bin/env bash
# install.sh — put haseen on an existing CachyOS (or Arch) install.
#
# 1. Preflight: refuse NixOS (use the flake) and unknown distros.
# 2. Install the tree: bin/ -> PREFIX/bin, share/haseen -> PREFIX/share/haseen,
#    systemd user units -> PREFIX/lib/systemd/user, desktop entries ->
#    PREFIX/share/applications, the app icon (`-i haseen`) ->
#    PREFIX/share/icons/hicolor. PREFIX defaults to
#    /usr/local because these files are not owned by a package (yet; see
#    plans/README.md, PKGBUILD phase).
# 3. Apply the default layers through the installed `haseen layer apply`.
#    At a terminal, without --layers or --yes, a picker chooses the layers and
#    the optional setup steps first (all optional pieces start off) and
#    remembers the choice in ~/.config/haseen/install.toml; a re-run offers to
#    reuse it (share/haseen/lib/install-picker.sh, plans/063-install-picker.md).
#
# Everything privileged goes through the common.sh helpers; --dry-run prints
# the full plan and changes nothing.
set -Eeuo pipefail

REPO="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
export HASEEN_PATH="$REPO/share/haseen"
# shellcheck source=share/haseen/lib/preflight.sh
source "$HASEEN_PATH/lib/preflight.sh"
# shellcheck source=share/haseen/lib/branding.sh
source "$HASEEN_PATH/lib/branding.sh"
# shellcheck source=share/haseen/lib/install-picker.sh
source "$HASEEN_PATH/lib/install-picker.sh"

DEFAULT_LAYERS=(base chaotic omarchy-repo desktop theme shell)
PREFIX=/usr/local
LAYERS=()
TREE_ONLY=false
UNINSTALL=false
VAPT_GROUPS=''
PICK=false

usage() {
    cat <<EOF
Usage: ./install.sh [--dry-run] [--yes] [--prefix DIR] [--layers a,b,c] [--pick]
                    [--vapt-groups GROUP,...|all] [--tree-only] [--uninstall-tree]

  --layers      layers to apply (default: ${DEFAULT_LAYERS[*]})
                optional: secureboot ai dms gaming flatpak (haseen layer list)
  --pick        choose the layers and optional setup steps (keyd, fingerprint,
                geoclue, dotfiles) from a list, even when stdin is not a
                terminal; at a terminal this is the default unless --layers or
                --yes is given. The choice is saved to
                ~/.config/haseen/install.toml and offered again next time.
  --vapt-groups explicitly provision optional VAPT groups after the layers;
                use 'all' for all 25 groups. No VAPT tools are selected by default.
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
    --vapt-groups) VAPT_GROUPS="${2:?--vapt-groups needs groups or all}"; shift ;;
    --tree-only) TREE_ONLY=true ;;
    --pick) PICK=true ;;
    --uninstall-tree) UNINSTALL=true ;;
    -h | --help) usage; exit 0 ;;
    *) usage >&2; die "unknown argument: $1" ;;
    esac
    shift
done
LAYERS_GIVEN=false
((${#LAYERS[@]} == 0)) || LAYERS_GIVEN=true
if $PICK && { $LAYERS_GIVEN || $ASSUME_YES || $TREE_ONLY || $UNINSTALL; }; then
    die "--pick chooses interactively; it does not combine with --layers, --yes, --tree-only or --uninstall-tree"
fi
$LAYERS_GIVEN || LAYERS=("${DEFAULT_LAYERS[@]}")
if [[ -n $VAPT_GROUPS ]] && { $TREE_ONLY || $UNINSTALL; }; then
    die "--vapt-groups cannot be combined with --tree-only or --uninstall-tree"
fi
ordinary_layers=()
for layer in "${LAYERS[@]}"; do
    if [[ $layer == vapt ]]; then
        [[ -n $VAPT_GROUPS ]] || die "--layers vapt requires explicit --vapt-groups GROUP,...|all"
    else
        ordinary_layers+=("$layer")
    fi
done
LAYERS=("${ordinary_layers[@]}")
VAPT_ONLY=false
if [[ -n $VAPT_GROUPS ]] && ((${#LAYERS[@]} == 0)); then VAPT_ONLY=true; fi
# Validate optional selection before any tree or workstation mutation.
if [[ -n $VAPT_GROUPS ]]; then
    (
        LAYER_DIR="$HASEEN_PATH/layers/vapt"
        source "$LAYER_DIR/layer.sh"
        if [[ $VAPT_GROUPS == all ]]; then layer_precheck --all
        else layer_precheck --groups "$VAPT_GROUPS"
        fi
    )
fi
require_not_root

UNIT_DIR="$PREFIX/lib/systemd/user"
# Desktop entries (the dms:// link handler) go where XDG_DATA_DIRS finds them;
# the shell layer makes haseen-dms-url.desktop the default for dms:// links.
APP_DIR="$PREFIX/share/applications"
# The app icon for menus and notifications (`notify-send -i haseen`): the
# selected mark (haseen branding mark), the full one in the theme's accent and
# the symbolic one in currentColor, which GTK recolours.
ICON_DIR="$PREFIX/share/icons/hicolor"

uninstall_tree() {
    local f
    for f in "$REPO"/bin/haseen*; do
        run_root rm -f "$PREFIX/bin/${f##*/}"
    done
    for f in "$REPO"/share/haseen/systemd/user/*; do
        [[ -e $f ]] && run_root rm -f "$UNIT_DIR/${f##*/}"
    done
    for f in "$REPO"/share/haseen/default/applications/*.desktop; do
        [[ -e $f ]] && run_root rm -f "$APP_DIR/${f##*/}"
    done
    run_root rm -f "$ICON_DIR/scalable/apps/haseen.svg" "$ICON_DIR/symbolic/apps/haseen-symbolic.svg"
    run_root rm -rf "$PREFIX/share/haseen"
    info "haseen tree removed from $PREFIX"
}

install_tree() {
    local f
    # The sampling daemon is compiled into the tree before it is copied. With no
    # Go toolchain the build script says so and the tree ships without it: the
    # shell then finds no capability and hides what needs it (plan 032).
    if ! $VAPT_ONLY; then
        if $DRY_RUN; then
            echo "DRYRUN: tools/build-sidecar.sh"
        else
            "$REPO/tools/build-sidecar.sh"
        fi
    fi
    # Replace share/haseen atomically: copy beside, then swap.
    run_root rm -rf "$PREFIX/share/haseen.new" "$PREFIX/share/haseen.old"
    run_root install -d -m 0755 "$PREFIX/share"
    # Root-owned, not the checkout owner's: root commands (sudo haseen …) and the
    # greeter, which runs as another user, execute from this tree.
    run_root cp -R --preserve=mode,timestamps,links "$REPO/share/haseen" "$PREFIX/share/haseen.new"
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
    for f in "$REPO"/share/haseen/default/applications/*.desktop; do
        [[ -e $f ]] && install_root_file "$f" "$APP_DIR/${f##*/}" 0644
    done
    branding_svg mark "$(branding_accent)" | write_root_file "$ICON_DIR/scalable/apps/haseen.svg"
    install_root_file "$(branding_file symbolic)" "$ICON_DIR/symbolic/apps/haseen-symbolic.svg" 0644
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

# The guided choice: asked for (--pick) or at a terminal with nothing decided
# on the command line. Piped or --yes runs keep the defaults and ask nothing.
PICKED=false
if ! $LAYERS_GIVEN && ! $ASSUME_YES && ! $TREE_ONLY && [[ -z $VAPT_GROUPS ]] && { $PICK || [[ -t 0 ]]; }; then
    picker_run "${DEFAULT_LAYERS[@]}"
    LAYERS=("${PICK_LAYERS[@]}")
    PICKED=true
fi

selection="${LAYERS[*]}"
[[ -z $VAPT_GROUPS ]] || selection+="${selection:+; }vapt groups=$VAPT_GROUPS"
confirm "Install haseen into $PREFIX and apply: $selection${PICK_SETUP[*]:+, then setup: ${PICK_SETUP[*]}}?" || exit 1
if $PICKED; then picker_save; fi
install_tree
$TREE_ONLY && exit 0

# Under --dry-run nothing was copied, so plan the layers from the checkout.
haseen_bin="$PREFIX/bin/haseen"
$DRY_RUN && haseen_bin="$REPO/bin/haseen"
# Normalize the checkout path as well as the installed path; the installed tree
# is absent during --dry-run.
installed_haseen_path="$(readlink -f -- "$(dirname "$haseen_bin")/../share/haseen")"
flags=()
$DRY_RUN && flags+=(--dry-run)
$ASSUME_YES && flags+=(--yes)
# A HOME haseen has run in (a migration ledger, the shell config, or a theme
# set) is an upgrade even when no migration was ever recorded; decided before
# the layers write theme.name.
fresh_home=true
if [[ -d $HASEEN_USER_STATE/migrations || -e $HASEEN_USER_CONFIG/shell.json || -e $HASEEN_USER_STATE/current/theme.name ]]; then
    fresh_home=false
fi
if ((${#LAYERS[@]})); then
    HASEEN_PATH="$installed_haseen_path" "$haseen_bin" layer apply "${LAYERS[@]}" "${flags[@]}"
fi
installer_rc=0
if [[ -n $VAPT_GROUPS ]]; then
    if [[ $VAPT_GROUPS == all ]]; then vapt_args=(--all)
    else vapt_args=(--groups "$VAPT_GROUPS")
    fi
    HASEEN_PATH="$installed_haseen_path" HASEEN_INSTALL_PATH="$PREFIX/share/haseen" "$haseen_bin" layer apply vapt "${flags[@]}" -- "${vapt_args[@]}" || installer_rc=$?
fi
# Tooling-only opt-in does not apply hardware quirks or unrelated migrations.
$VAPT_ONLY && exit "$installer_rc"

# A fresh HOME has nothing to upgrade, so its migrations are recorded as
# sealed; an existing haseen user gets what is genuinely pending run.
if ! $fresh_home; then
    HASEEN_PATH="$installed_haseen_path" "$haseen_bin" migrate "${flags[@]}"
else
    HASEEN_PATH="$installed_haseen_path" "$haseen_bin" migrate --seal "${flags[@]}"
    # A first install also seeds haseen.nvim when ~/.config/nvim is absent
    # (plan 065). An existing config is left alone, and later runs never seed.
    HASEEN_PATH="$installed_haseen_path" "$haseen_bin" setup nvim --if-absent "${flags[@]}" ||
        warn "haseen.nvim was not seeded; run: haseen setup nvim"
fi

# Hardware quirks are matched against this machine and applied once each; the
# ledger makes a reinstall and every later run a no-op.
HASEEN_PATH="$installed_haseen_path" "$haseen_bin" hw apply "${flags[@]}"

# The optional setup steps the picker chose; none otherwise.
picker_run_setup "$haseen_bin" "${flags[@]}"
exit "$installer_rc"
