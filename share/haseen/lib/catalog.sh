# shellcheck shell=bash
# catalog.sh — the app catalogue behind `haseen install|remove`. Sourced,
# never executed.
#
# Catalogue: share/haseen/default/catalog.json (plan 017). Every entry has
# id, category, label, icon, source (flatpak|pacman|aur|mise), ref and an
# optional `when` bash guard. Extras: `family` (fonts), `layer` (installed by
# applying that haseen layer), `needs` (pacman packages a mise toolchain
# builds against), `container` (a Docker database; ref is then the docker
# package that runs it), `pullsOmarchy` (see the guard below).
#
# `"source": "aur"` means "not in the official repos", not "built from the
# AUR": it goes through pkg_install_aur, which tries an enabled repo, then
# Chaotic-AUR, then [omarchy], and builds from the AUR only as the last
# resort. [omarchy]-repo apps (flea, localsend, omacalc, herdr) use it.
#
# Flatpaks live in the per-user installation (`flatpak --user`): installing,
# updating and removing apps then needs no root and no polkit prompt, and the
# flatpak layer adds the Flathub remote to that scope (layers/flatpak).
#
# Install-state probes read files only (the pacman database, the flatpak and
# mise install dirs), never `pacman`/`flatpak`/`mise`, so the menu can ask for
# every entry in one fast call and the probes work against test fixtures.

[[ -n ${HASEEN_CATALOG_SH:-} ]] && return 0
HASEEN_CATALOG_SH=1
# shellcheck source=packages.sh
source "$(dirname "${BASH_SOURCE[0]}")/packages.sh"
# shellcheck source=terminal.sh
source "$(dirname "${BASH_SOURCE[0]}")/terminal.sh"
# unit_enabled and friends: read-only probes through sysroot_path.
# shellcheck source=../layers/base/lib.sh
source "$(dirname "${BASH_SOURCE[0]}")/../layers/base/lib.sh"

HASEEN_CATALOG=${HASEEN_CATALOG:-$HASEEN_PATH/default/catalog.json}
FLATHUB_URL=https://dl.flathub.org/repo/flathub.flatpakrepo
FLATPAK_ID_RE='^[A-Za-z][A-Za-z0-9_-]*(\.[A-Za-z0-9_-]+){2,}$'

# The haseen router, for calling sibling commands (layer apply, font set).
HASEEN_BIN="$(cd "$HASEEN_PATH/../../bin" 2>/dev/null && pwd || true)"
HASEEN_EXE="${HASEEN_BIN:+$HASEEN_BIN/}haseen"

flatpak_user_dir() { printf '%s\n' "${XDG_DATA_HOME:-$HOME/.local/share}/flatpak"; }
mise_data_dir() { printf '%s\n' "${MISE_DATA_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/mise}"; }

# --- catalogue lookups --------------------------------------------------------

# catalog_field ID FIELD — one field of entry ID ("" when absent). Arrays are
# printed one element per line.
catalog_field() {
    jq -r --arg id "$1" --arg f "$2" \
        '.entries[] | select(.id == $id) | .[$f] // empty | if type == "array" then .[] else . end' \
        "$HASEEN_CATALOG"
}

catalog_has() { jq -e --arg id "$1" 'any(.entries[]; .id == $id)' "$HASEEN_CATALOG" >/dev/null; }

# catalog_resolve NAME [CATEGORY] — the entry id NAME refers to: an id, a
# label or a ref (package or Flatpak id), case-insensitive, optionally limited
# to one category. Dies when nothing matches.
catalog_resolve() {
    local name="$1" category="${2:-}" id
    id="$(jq -r --arg n "${name,,}" --arg c "$category" '
        [.entries[] | select($c == "" or .category == $c)
         | select((.id | ascii_downcase) == $n or (.label | ascii_downcase) == $n
                  or ((.ref | ascii_downcase) | split(" ") | index($n)))
        ][0].id // empty' "$HASEEN_CATALOG")"
    [[ -n $id ]] || die "'$name' is not in the catalogue${category:+ ($category)}. List: haseen install app --list${category:+ $category}"
    printf '%s\n' "$id"
}

# catalog_list [CATEGORY] — "id<TAB>source<TAB>label" rows.
catalog_list() {
    jq -r --arg c "${1:-}" '.entries[] | select($c == "" or .category == $c) | [.id, .source, .label] | @tsv' "$HASEEN_CATALOG"
}

# catalog_when_ok ID — the entry's `when` guard holds (or it has none).
catalog_when_ok() {
    local guard
    guard="$(catalog_field "$1" when)"
    [[ -z $guard ]] || bash -c "$guard" &>/dev/null
}

# mise_tool SPEC — "erlang@latest" -> "erlang".
mise_tool() { printf '%s\n' "${1%@*}"; }

# --- install state (files only) -----------------------------------------------

declare -gA CATALOG_PKGS=()
_catalog_pkgs_loaded=false

# catalog_load_pkgs — every installed pacman package name into CATALOG_PKGS,
# from one read of the local database (<name>-<pkgver>-<pkgrel> dirs).
catalog_load_pkgs() {
    $_catalog_pkgs_loaded && return 0
    _catalog_pkgs_loaded=true
    local d name
    for d in "$(sysroot_path /var/lib/pacman/local)"/*/; do
        [[ -d $d ]] || continue
        name="$(basename "$d")"
        name="${name%-*}"
        CATALOG_PKGS["${name%-*}"]=1
    done
}

catalog_pkg_installed() {
    catalog_load_pkgs
    [[ -n ${CATALOG_PKGS[$1]:-} ]]
}

flatpak_app_installed() {
    [[ -d $(flatpak_user_dir)/app/$1 || -d $(sysroot_path /var/lib/flatpak/app)/$1 ]]
}

mise_tool_installed() {
    compgen -G "$(mise_data_dir)/installs/$(mise_tool "$1")/*" >/dev/null
}

# catalog_installed ID SOURCE REF CONTAINER — true when every piece of the
# entry is present. Docker databases cannot be probed without root (the
# docker socket and /var/lib/docker are root-only), so they never count as
# installed; `haseen remove app` still removes them.
catalog_installed() {
    local id="$1" source="$2" ref="$3" container="$4" r
    [[ -z $container ]] || return 1
    for r in $ref; do
        case "$source" in
        flatpak) flatpak_app_installed "$r" || return 1 ;;
        pacman | aur) catalog_pkg_installed "$r" || return 1 ;;
        mise) mise_tool_installed "$r" || return 1 ;;
        *) return 1 ;;
        esac
    done
}

# catalog_installed_ids [ID] — print installed entry ids; with ID, exit 0/1.
catalog_installed_ids() {
    local want="${1:-}" id source ref container found=1
    while IFS=$'\t' read -r id source ref container; do
        [[ -z $want || $id == "$want" ]] || continue
        if catalog_installed "$id" "$source" "$ref" "$container"; then
            [[ -n $want ]] || printf '%s\n' "$id"
            found=0
        fi
    done < <(jq -r '.entries[] | [.id, .source, .ref, (.container.name // "")] | @tsv' "$HASEEN_CATALOG")
    [[ -z $want ]] && return 0
    return "$found"
}

# --- flatpak --------------------------------------------------------------------

require_flatpak() {
    have flatpak || $DRY_RUN || die "flatpak is not installed. Run: haseen layer apply flatpak"
}

# flathub_user_remote_present — Flathub is configured in the user installation
# (read from the repo config, not `flatpak remotes`, so this stays a file read).
flathub_user_remote_present() {
    grep -qs '^\[remote "flathub"\]' "$(flatpak_user_dir)/repo/config"
}

ensure_flathub_user() {
    flathub_user_remote_present && return 0
    run flatpak remote-add --user --if-not-exists flathub "$FLATHUB_URL"
}

flatpak_install_app() {
    local id="$1"
    [[ $id =~ $FLATPAK_ID_RE ]] || die "not a Flatpak app id: '$id' (expected e.g. org.mozilla.firefox)"
    require_flatpak
    ensure_flathub_user
    if flatpak_app_installed "$id"; then
        info "$id is already installed"
        return 0
    fi
    local flags=(--user)
    $ASSUME_YES && flags+=(-y)
    run flatpak install "${flags[@]}" flathub "$id"
}

flatpak_remove_app() {
    local id="$1" scope=--user
    [[ $id =~ $FLATPAK_ID_RE ]] || die "not a Flatpak app id: '$id'"
    require_flatpak
    if [[ ! -d $(flatpak_user_dir)/app/$id ]]; then
        if [[ -d $(sysroot_path /var/lib/flatpak/app)/$id ]]; then
            scope=--system
        else
            info "$id is not installed"
            return 0
        fi
    fi
    local flags=("$scope")
    $ASSUME_YES && flags+=(-y)
    run flatpak uninstall "${flags[@]}" "$id"
}

# --- pacman / AUR -----------------------------------------------------------------

check_pkg_names() {
    local p
    for p in "$@"; do
        [[ $p =~ $PKG_NAME_RE ]] || die "invalid package name: '$p'"
    done
}

pkg_remove() {
    local present=() p
    for p in "$@"; do
        catalog_pkg_installed "$p" && present+=("$p")
    done
    if ((${#present[@]} == 0)); then
        info "not installed: $*"
        return 0
    fi
    local flags=(-Rns)
    $ASSUME_YES && flags+=(--noconfirm)
    run_root pacman "${flags[@]}" "${present[@]}"
}

# --- mise ------------------------------------------------------------------------

mise_install_tools() {
    local spec
    have mise || pkg_install mise
    for spec in "$@"; do
        run mise use --global "$spec"
    done
    # haseen's shell fragment runs `mise activate` itself
    # (default/shell/init.sh), so there is nothing to advise once the rc
    # includes it. A hand-wired `mise activate` counts too, and fish is not a
    # shell haseen seeds, so it keeps the manual answer.
    local rc
    for rc in "$HOME/.bashrc" "$HOME/.zshrc" "${XDG_CONFIG_HOME:-$HOME/.config}/fish/config.fish"; do
        grep -qsE 'mise activate|default/shell/init\.sh' "$rc" && return 0
    done
    info "mise tools reach PATH through haseen's shell fragment: run 'haseen seed user'"
}

mise_remove_tools() {
    local spec
    have mise || $DRY_RUN || die "mise is not installed"
    for spec in "$@"; do
        # unuse drops the tool from the global config and prunes its versions.
        run mise unuse --global "$(mise_tool "$spec")"
    done
}

# --- docker databases -----------------------------------------------------------

docker_ready() {
    pkg_install docker
    unit_enabled docker.socket || run_root systemctl enable --now docker.socket
}

container_install() {
    local id="$1" name image port env=() e args
    name="$(jq -r --arg id "$id" '.entries[] | select(.id == $id) | .container.name' "$HASEEN_CATALOG")"
    image="$(jq -r --arg id "$id" '.entries[] | select(.id == $id) | .container.image' "$HASEEN_CATALOG")"
    port="$(jq -r --arg id "$id" '.entries[] | select(.id == $id) | .container.port' "$HASEEN_CATALOG")"
    mapfile -t env < <(jq -r --arg id "$id" '.entries[] | select(.id == $id) | .container.env[]' "$HASEEN_CATALOG")
    docker_ready
    # Bound to loopback only: these are passwordless development databases.
    args=(run -d --restart unless-stopped -p "127.0.0.1:$port:$port" --name "$name")
    for e in "${env[@]}"; do args+=(-e "$e"); done
    run_root docker "${args[@]}" "$image"
    info "$name listens on 127.0.0.1:$port"
}

container_remove() {
    local name
    name="$(jq -r --arg id "$1" '.entries[] | select(.id == $id) | .container.name' "$HASEEN_CATALOG")"
    have docker || $DRY_RUN || die "docker is not installed"
    run_root docker rm -f "$name"
}

# --- the [omarchy] dependency-pull guard -------------------------------------------
#
# `omarchy` and `omarchy-settings` stay in PKG_DENY: haseen never installs them
# as a target (ADR 0001, lib/packages.sh). flea is the exception the owner
# asked for. It is a leaf app in the [omarchy] repo that hard-depends on
# `omarchy`, so pacman drags the pair in as dependencies of a package that is
# itself allowed. A catalogue entry declares that with "pullsOmarchy": true,
# and this prints the whole closure plus the system files it will drop, then
# asks. Nothing else changes: `haseen install package omarchy` is still
# refused.
#
# Both lists were read from this machine on 2026-10-05, never invented:
#   pacman -Si flea             -> Depends On: ... omarchy ...
#   pacman -Si omarchy          -> OMARCHY_CLOSURE below (omarchy 4.0.4-1)
#   pacman -Ql omarchy-settings -> OMARCHY_COLLISIONS below
# Asking pacman at run time is not an option: it is a privileged/network call,
# and the fixture tests and the dry-run contract must not make one.
# OMARCHY_CLOSURE_READ dates them: the closure changes with omarchy releases,
# so the prompt says when it was read and that pacman lists the real one.
OMARCHY_CLOSURE_READ="2026-10-05, omarchy 4.0.4-1"
OMARCHY_CLOSURE="omarchy omarchy-keyring omarchy-settings=4.0.4 hyprland quickshell uwsm sddm \
xdg-desktop-portal-hyprland wireplumber pipewire gnome-keyring gum jq git perl fakeroot \
pacman-contrib ttf-jetbrains-mono-nerd-basic limine limine-mkinitcpio-hook limine-snapper-sync snapper"

# "<file omarchy-settings owns>|<the haseen subsystem it lands on>".
OMARCHY_COLLISIONS=(
    "/etc/fonts/conf.d/50-omarchy.conf|fonts: haseen's fontconfig seed and theme render"
    "/etc/limine-entry-tool.d/omarchy-defaults.conf|Limine entries: plan 002 Secure Boot"
    "/etc/limine-entry-tool.d/omarchy-uki.conf|Limine entries: plan 002 Secure Boot"
    "/etc/mkinitcpio.conf.d/omarchy_hooks.conf|initramfs HOOKS: plan 033 hibernation"
    "/etc/sddm.conf.d/10-theme.conf|display manager: haseen uses greetd + tuigreet"
    "/etc/sddm.conf.d/10-wayland.conf|display manager: haseen uses greetd + tuigreet"
    "/usr/lib/environment.d/10-omarchy-fcitx.conf|input method: haseen's fcitx5 seed"
    "/usr/share/applications/mimeapps.list|default handlers: haseen's vendor mimeapps.list"
    "/usr/share/xdg-terminal-exec/hyprland-xdg-terminals.list|default terminal: haseen's vendor list"
)

# catalog_confirm_omarchy ID — show the closure and the collisions, then ask.
# --yes answers it; --dry-run prints it and carries on (confirm does both).
catalog_confirm_omarchy() {
    local id="$1" label row p
    label="$(catalog_field "$id" label)"
    warn "$label depends on the 'omarchy' package, which haseen replaces (docs/decisions/0001)."
    info "pacman will pull in this dependency closure (as read on $OMARCHY_CLOSURE_READ; pacman lists the current one before it installs): $OMARCHY_CLOSURE"
    info "omarchy-settings then owns these system files (as read on $OMARCHY_CLOSURE_READ), which land on haseen subsystems:"
    for row in "${OMARCHY_COLLISIONS[@]}"; do
        p="${row%%|*}"
        printf '    %-56s %s\n' "$p" "${row#*|}"
    done
    info "pacman owns those paths afterwards: haseen does not fight it, and removing $label with 'haseen remove app $id' leaves them behind (pacman -Rns omarchy omarchy-settings does not, but read ADR 0001 first)."
    confirm "Install $label and the omarchy dependency chain?" || die "not confirmed; nothing was installed"
}

# catalog_guard_packages NAME... — `haseen install package|aur` name packages
# directly. A package that a pullsOmarchy entry installs (flea, also as
# omarchy/flea) gets the same confirmation as `haseen install app <id>`, so
# the bare routes are not a way around it.
catalog_guard_packages() {
    local ids=() id
    # Collected first: the confirmation reads stdin, which a `while read` loop
    # would hand it.
    mapfile -t ids < <(jq -r '
        [$ARGS.positional[] | sub("^.*/"; "")] as $names
        | .entries[] | select(.pullsOmarchy == true)
        | select(any(.ref | splits(" +") | sub("^.*/"; ""); . as $r | any($names[]; . == $r)))
        | .id' "$HASEEN_CATALOG" --args "$@")
    for id in "${ids[@]}"; do
        catalog_confirm_omarchy "$id"
    done
}

# --- per-entry extra steps ---------------------------------------------------------

XPAD_BLACKLIST=/etc/modprobe.d/haseen-xpadneo.conf
XPAD_LOAD=/etc/modules-load.d/haseen-xpadneo.conf

user_in_group() {
    local line
    line="$(grep -E "^$1:" "$(sysroot_path /etc/group)" 2>/dev/null || true)"
    [[ ",${line##*:}," == *",${USER:-$(id -un)},"* ]]
}

# catalog_post_install ID — what a package alone does not do.
catalog_post_install() {
    case "$1" in
    xbox-controllers)
        # xpadneo replaces the in-kernel xpad driver for Bluetooth pads.
        printf 'blacklist xpad\n' | write_root_file "$XPAD_BLACKLIST"
        printf 'hid_xpadneo\n' | write_root_file "$XPAD_LOAD"
        user_in_group input || run_root usermod -aG input "${USER:-$(id -un)}"
        info "xpadneo: reboot (or log out and back in) to switch drivers, then pair the controller over Bluetooth"
        ;;
    docker)
        unit_enabled docker.socket || run_root systemctl enable --now docker.socket
        info "docker: haseen does not add you to the docker group (it is root-equivalent); run docker as root"
        ;;
    tailscale)
        unit_enabled tailscaled.service || run_root systemctl enable --now tailscaled.service
        info "tailscale: sign in by running 'tailscale up' as root"
        ;;
    nordvpn)
        unit_enabled nordvpnd.service || run_root systemctl enable --now nordvpnd.service
        user_in_group nordvpn || run_root usermod -aG nordvpn "${USER:-$(id -un)}"
        info "nordvpn: log out and back in, then 'nordvpn login'"
        ;;
    esac
}

catalog_post_remove() {
    case "$1" in
    xbox-controllers) run_root rm -f "$XPAD_BLACKLIST" "$XPAD_LOAD" ;;
    tailscale) unit_enabled tailscaled.service && run_root systemctl disable --now tailscaled.service ;;
    nordvpn) unit_enabled nordvpnd.service && run_root systemctl disable --now nordvpnd.service ;;
    esac
    return 0
}

# font_apply FAMILY — switch to the font when `haseen font set` exists.
font_apply() {
    local family="$1"
    if [[ -n $HASEEN_BIN && ( -x $HASEEN_BIN/haseen-font-set || -x $HASEEN_BIN/haseen-font ) ]]; then
        # Through run: in a dry run the font is not installed yet, so
        # `font set` would rightly refuse it.
        run "$HASEEN_EXE" font set "$family"
    else
        info "installed $family; select it in your terminal and shell font settings"
    fi
}

# --- dispatch --------------------------------------------------------------------

catalog_install() {
    local id="$1" source ref layer container family r refs=() needs=()
    local pulls_omarchy
    source="$(catalog_field "$id" source)"
    ref="$(catalog_field "$id" ref)"
    layer="$(catalog_field "$id" layer)"
    container="$(catalog_field "$id" container)"
    family="$(catalog_field "$id" family)"
    mapfile -t needs < <(catalog_field "$id" needs)
    read -ra refs <<<"$ref"
    catalog_when_ok "$id" || die "$(catalog_field "$id" label) is not available on this machine (guard: $(catalog_field "$id" when))"
    pulls_omarchy="$(catalog_field "$id" pullsOmarchy)"
    if [[ $pulls_omarchy == true ]]; then
        catalog_confirm_omarchy "$id"
    fi
    info "installing $(catalog_field "$id" label) ($source: $ref)"
    case "$source" in
    flatpak) for r in "${refs[@]}"; do flatpak_install_app "$r"; done ;;
    pacman)
        check_pkg_names "${refs[@]}"
        if [[ -n $container ]]; then
            container_install "$id"
        elif [[ -n $layer ]]; then
            # Steam needs [multilib], 32-bit drivers matched to the GPU and
            # the gamemode group: the gaming layer does all of that.
            local largs=()
            $DRY_RUN && largs+=(--dry-run)
            $ASSUME_YES && largs+=(--yes)
            "$HASEEN_EXE" layer apply "$layer" "${largs[@]}"
        else
            pkg_install "${refs[@]}"
        fi
        ;;
    aur)
        check_pkg_names "${refs[@]}"
        pkg_install_aur "${refs[@]}"
        ;;
    mise)
        ((${#needs[@]} == 0)) || pkg_install "${needs[@]}"
        mise_install_tools "${refs[@]}"
        ;;
    *) die "catalogue entry $id has unknown source '$source'" ;;
    esac
    catalog_post_install "$id"
    [[ -z $family ]] || font_apply "$family"
}

catalog_remove() {
    local id="$1" source ref container r refs=()
    source="$(catalog_field "$id" source)"
    ref="$(catalog_field "$id" ref)"
    container="$(catalog_field "$id" container)"
    read -ra refs <<<"$ref"
    info "removing $(catalog_field "$id" label) ($source: $ref)"
    case "$source" in
    flatpak) for r in "${refs[@]}"; do flatpak_remove_app "$r"; done ;;
    pacman | aur)
        if [[ -n $container ]]; then
            container_remove "$id"
        else
            catalog_post_remove "$id"
            pkg_remove "${refs[@]}"
        fi
        ;;
    mise) mise_remove_tools "${refs[@]}" ;;
    *) die "catalogue entry $id has unknown source '$source'" ;;
    esac
}
