# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 017: the app catalogue, `haseen install|remove` dispatch per source,
# update/time/password/restart/refresh plans, the LUKS typed-confirmation
# gate, the flatpak layer and the floating-terminal re-exec. Hermetic: a copy
# of the desk-cachyos-amd fixture extended per case, stub PATH, scratch HOME.

CATALOG="$HASEEN_PATH/default/catalog.json"

# cat_root — the fixture copy every case reads as / (sets ROOT).
cat_root() {
    ROOT="$SANDBOX/root"
    cp -a "$FIXTURES/desk-cachyos-amd" "$ROOT"
    mkdir -p "$ROOT/var/lib/pacman/local" "$ROOT/proc/self" "$ROOT/sys/block" \
        "$ROOT/usr/share/zoneinfo/Europe" "$ROOT/var/lib/flatpak/app"
    touch "$ROOT/usr/share/zoneinfo/Europe/Berlin"
    export HASEEN_SYSROOT="$ROOT"
    # Read-only probes and user-level tools a dry run must never reach.
    local c
    for c in mise fwupdmgr timedatectl passwd rfkill nmcli fzf foot kitty alacritty ghostty; do
        stub "$c" "echo \"STUB-CALLED: $c \$*\" >&2; exit 97"
    done
    unset HYPRLAND_INSTANCE_SIGNATURE
    # Commands run inline: stdin here is not a TTY, and the real terminal must
    # never open on the live session. The re-exec test below unsets this.
    export HASEEN_INLINE=1 TERMINAL=foot
}

pkg_fixture() { mkdir -p "$ROOT/var/lib/pacman/local/$1-1.0-1"; }

# --- catalogue validity --------------------------------------------------------
assert_eq "catalog: valid JSON" 0 "$(jq empty "$CATALOG" >/dev/null 2>&1; echo $?)"
assert_eq "catalog: unique ids" "" "$(jq -r '[.entries[].id] | group_by(.) | map(select(length > 1) | .[0]) | .[]' "$CATALOG")"
assert_eq "catalog: known sources only" "" "$(jq -r '.entries[] | select(.source | IN("flatpak","pacman","aur","mise") | not) | .id' "$CATALOG")"
assert_eq "catalog: required fields" "" "$(jq -r '.entries[] | select([.id,.label,.icon,.source,.ref,.category] | any(. == null or . == "")) | .id' "$CATALOG")"
assert_eq "catalog: categories exist" "" "$(jq -r '[.categories[].id] as $c | .entries[] | select(.category | IN($c[]) | not) | .id' "$CATALOG")"
assert_eq "catalog: no web apps" "" "$(jq -r '.entries[] | select((.id + " " + .label + " " + .ref | ascii_downcase) | test("webapp|web app|https?:|xbox cloud|xbox-cloud")) | .id' "$CATALOG")"
assert_eq "catalog: flatpak refs are app ids" "" "$(jq -r '.entries[] | select(.source == "flatpak") | .ref' "$CATALOG" | grep -Ev '^[A-Za-z][A-Za-z0-9_-]*(\.[A-Za-z0-9_-]+){2,}$' || true)"
assert_eq "catalog: package refs are package names" "" "$(jq -r '.entries[] | select(.source == "pacman" or .source == "aur") | .ref | split(" ")[]' "$CATALOG" | grep -Ev '^[a-z0-9@._+][a-z0-9@._+-]*$' || true)"
assert_eq "catalog: fonts carry a family" "" "$(jq -r '.entries[] | select(.category == "font" and (.family // "") == "") | .id' "$CATALOG")"
assert_eq "catalog: dev toolchains use mise or docker" "" "$(jq -r '.entries[] | select(.category == "development" and .source != "mise" and (.ref | test("docker") | not)) | .id' "$CATALOG")"
assert_contains "catalog: Flathub verification date" "$(jq -r .flathubVerified "$CATALOG")" "2026-"
assert_contains "catalog: browsers are Flatpaks" "$(jq -r '[.entries[] | select(.category == "browser") | .source] | unique | join(",")' "$CATALOG")" "flatpak"
# Helium is not on Flathub (plan 070): helium-browser-bin from Chaotic-AUR.
# Brave Origin neither (plan 068, merged menu): brave-origin-bin.
assert_eq "catalog: browsers only Flatpaks, but Helium and Brave Origin" "flatpak" "$(jq -r '[.entries[] | select(.category == "browser" and .id != "helium" and .id != "brave-origin") | .source] | unique | join(",")' "$CATALOG")"

# --- install dispatch per source (dry-run) ------------------------------------
sandbox catalog-install
cat_root
all=""

capture haseen install app firefox --dry-run
all+="$OUTPUT"
assert_status "flatpak: exit" 0 "$STATUS"
assert_contains "flatpak: adds Flathub for the user" "$OUTPUT" "DRYRUN: flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo"
assert_contains "flatpak: installs into the user installation" "$OUTPUT" "DRYRUN: flatpak install --user flathub org.mozilla.firefox"

mkdir -p "$HOME/.local/share/flatpak/repo"
printf '[remote "flathub"]\nurl=https://dl.flathub.org/repo/\n' >"$HOME/.local/share/flatpak/repo/config"
capture haseen install flatpak com.spotify.Client --dry-run --yes
all+="$OUTPUT"
assert_not_contains "flatpak: remote not re-added" "$OUTPUT" "remote-add"
assert_contains "flatpak id: -y with --yes" "$OUTPUT" "DRYRUN: flatpak install --user -y flathub com.spotify.Client"
capture haseen install flatpak 'evil;rm -rf' --dry-run
assert_status "flatpak id: bad id refused" 1 "$STATUS"
assert_contains "flatpak id: bad id message" "$OUTPUT" "not a Flatpak app id"

capture haseen install app kitty --dry-run
all+="$OUTPUT"
assert_contains "pacman: repo package" "$OUTPUT" "DRYRUN: sudo pacman -S --needed kitty"

capture haseen install app Cursor --dry-run
all+="$OUTPUT"
assert_contains "aur: by label, via the helper" "$OUTPUT" "DRYRUN: paru -S --needed cursor-bin"

capture haseen install app xbox-controllers --dry-run
all+="$OUTPUT"
assert_contains "aur: xpadneo" "$OUTPUT" "DRYRUN: paru -S --needed xpadneo-dkms"
assert_contains "aur: xpad blacklisted" "$OUTPUT" "DRYRUN: write /etc/modprobe.d/haseen-xpadneo.conf"
assert_contains "aur: input group" "$OUTPUT" "usermod -aG input"

capture haseen install dev python --dry-run
all+="$OUTPUT"
assert_contains "mise: python" "$OUTPUT" "DRYRUN: mise use --global python@latest"
assert_contains "mise: uv" "$OUTPUT" "DRYRUN: mise use --global uv@latest"
capture haseen install dev ruby --dry-run
all+="$OUTPUT"
assert_contains "mise: build deps from pacman" "$OUTPUT" "DRYRUN: sudo pacman -S --needed libyaml"
capture haseen install dev cobol --dry-run
assert_status "dev: unknown language refused" 1 "$STATUS"

capture haseen install font "Fira Code" --dry-run
all+="$OUTPUT"
assert_contains "font: nerd font package" "$OUTPUT" "DRYRUN: sudo pacman -S --needed ttf-firacode-nerd"
if [[ -x $REPO/bin/haseen-font-set || -x $REPO/bin/haseen-font ]]; then
    assert_contains "font: switches to it" "$OUTPUT" "FiraCode Nerd Font"
else
    assert_contains "font: hint without font set" "$OUTPUT" "installed FiraCode Nerd Font"
fi
capture haseen install font kitty --dry-run
assert_status "font: non-font refused" 1 "$STATUS"

capture haseen install app postgresql --dry-run
all+="$OUTPUT"
assert_contains "docker db: engine" "$OUTPUT" "DRYRUN: sudo pacman -S --needed docker"
assert_contains "docker db: socket" "$OUTPUT" "DRYRUN: sudo systemctl enable --now docker.socket"
assert_contains "docker db: loopback container" "$OUTPUT" "DRYRUN: sudo docker run -d --restart unless-stopped -p 127.0.0.1:5432:5432 --name postgres18 -e POSTGRES_HOST_AUTH_METHOD=trust postgres:18"

capture haseen install app steam --dry-run
all+="$OUTPUT"
assert_status "steam: exit" 0 "$STATUS"
assert_contains "steam: through the gaming layer" "$OUTPUT" "apply order: base chaotic desktop gaming"
assert_contains "steam: 32-bit drivers come along" "$OUTPUT" "lib32-vulkan-radeon"

capture haseen install package htop 'bad;name' --dry-run
assert_status "package: bad name refused" 1 "$STATUS"
assert_contains "package: bad name message" "$OUTPUT" "invalid package name"
capture haseen install package htop --dry-run
all+="$OUTPUT"
assert_contains "package: named" "$OUTPUT" "DRYRUN: sudo pacman -S --needed htop"
capture haseen install package --dry-run
all+="$OUTPUT"
assert_contains "package: picker plan" "$OUTPUT" "pick packages from 'pacman -Slq' with fzf"
capture haseen install aur --dry-run
all+="$OUTPUT"
assert_contains "aur: picker plan" "$OUTPUT" "-Slqa' with fzf"
capture haseen install app no-such-app --dry-run
assert_status "app: unknown refused" 1 "$STATUS"
assert_contains "app: unknown message" "$OUTPUT" "not in the catalogue"

assert_dry_pure "install" "$all"
assert_eq "install dry-runs wrote nothing but the fixture remote" "$HOME/.local/share/flatpak/repo/config" "$(find "$HOME" -type f)"

# --- installed detection (files only) -------------------------------------------
pkg_fixture kitty
pkg_fixture ttf-firacode-nerd
mkdir -p "$HOME/.local/share/flatpak/app/org.mozilla.firefox" "$ROOT/var/lib/flatpak/app/com.spotify.Client" \
    "$HOME/.local/share/mise/installs/python/3.14.0" "$HOME/.local/share/mise/installs/uv/0.9.0"
capture haseen install app --installed
assert_eq "installed: ids from files" "$(printf '%s\n' firefox kitty spotify fira-code python)" "$OUTPUT"
capture haseen install app --installed kitty
assert_status "installed: one id yes" 0 "$STATUS"
capture haseen install app --installed zed
assert_status "installed: one id no" 1 "$STATUS"
capture haseen install app --list font
assert_contains "list: fonts" "$OUTPUT" $'iosevka\tpacman\tIosevka'
assert_not_contains "list: category filter" "$OUTPUT" "firefox"

capture haseen install app firefox --dry-run
assert_contains "flatpak: already installed is a no-op" "$OUTPUT" "org.mozilla.firefox is already installed"
assert_not_contains "flatpak: no reinstall" "$OUTPUT" "flatpak install"

# --- remove dispatch -----------------------------------------------------------
all=""
capture haseen remove app firefox --dry-run
all+="$OUTPUT"
assert_contains "remove flatpak: user scope" "$OUTPUT" "DRYRUN: flatpak uninstall --user org.mozilla.firefox"
capture haseen remove flatpak com.spotify.Client --dry-run
all+="$OUTPUT"
assert_contains "remove flatpak: system scope fallback" "$OUTPUT" "DRYRUN: flatpak uninstall --system com.spotify.Client"
capture haseen remove app kitty --dry-run
all+="$OUTPUT"
assert_contains "remove pacman" "$OUTPUT" "DRYRUN: sudo pacman -Rns kitty"
capture haseen remove app helix --dry-run
all+="$OUTPUT"
assert_contains "remove pacman: not installed is a no-op" "$OUTPUT" "not installed: helix"
capture haseen remove dev python --dry-run
all+="$OUTPUT"
assert_contains "remove mise" "$OUTPUT" "DRYRUN: mise unuse --global python"
assert_contains "remove mise: every tool" "$OUTPUT" "DRYRUN: mise unuse --global uv"
capture haseen remove font fira-code --dry-run
all+="$OUTPUT"
assert_contains "remove font" "$OUTPUT" "DRYRUN: sudo pacman -Rns ttf-firacode-nerd"
capture haseen remove app redis --dry-run
all+="$OUTPUT"
assert_contains "remove docker db: container only" "$OUTPUT" "DRYRUN: sudo docker rm -f redis"
assert_not_contains "remove docker db: engine stays" "$OUTPUT" "pacman -Rns docker"
capture haseen remove package --dry-run
all+="$OUTPUT"
assert_contains "remove package: picker plan" "$OUTPUT" "'pacman -Qqe' with fzf"
assert_dry_pure "remove" "$all"

# --- update, time, password user, restart, refresh (dry-run) ------------------
all=""
capture haseen update --dry-run
all+="$OUTPUT"
assert_contains "update: opens on haseen's name" "$OUTPUT" "[*] haseen update: system"
assert_not_contains "update: never Omarchy's" "$OUTPUT" "Omarchy"
assert_contains "update: repos" "$OUTPUT" "DRYRUN: sudo pacman -Syu"
assert_contains "update: AUR" "$OUTPUT" "DRYRUN: paru -Sua"
assert_contains "update: user flatpaks" "$OUTPUT" "DRYRUN: flatpak update --user"
assert_contains "update: system flatpaks when present" "$OUTPUT" "DRYRUN: flatpak update --system"
# A machine that still carries the omarchy package has a pacman hook that aborts
# any -Syu not started by `omarchy update`; haseen update must get through it.
guard_root="$SANDBOX/omarchy-guard"
mkdir -p "$guard_root/usr/share/libalpm/hooks"
: >"$guard_root/usr/share/libalpm/hooks/00-omarchy-update-guard.hook"
capture env HASEEN_SYSROOT="$guard_root" haseen update --dry-run
assert_contains "update: passes Omarchy's pacman guard where it is installed" "$OUTPUT" \
    "DRYRUN: sudo env OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -Syu"
capture haseen update firmware --dry-run --yes
all+="$OUTPUT"
assert_contains "firmware: refresh" "$OUTPUT" "DRYRUN: fwupdmgr refresh --force"
assert_contains "firmware: update as root" "$OUTPUT" "DRYRUN: sudo fwupdmgr update"
capture haseen update kernel --dry-run
assert_status "update: unknown target" 2 "$STATUS"

# A real (not dry) update on a terminal, as the floating terminal runs it:
# the banner must not stop it (plan 060: it read a file plan 059 removed, so
# every click on an update button ended at "No such file" before pacman).
# Root, AUR and Flatpak are stubs that only record their arguments.
tty_bin="$SANDBOX/update-tty"
mkdir -p "$tty_bin"
for c in sudo paru flatpak; do
    printf '#!/bin/sh\necho "RAN: %s $*"\n' "$c" >"$tty_bin/$c"
    chmod +x "$tty_bin/$c"
done
capture env PATH="$tty_bin:$PATH" script -qec "haseen update" /dev/null
assert_status "update on a TTY: completes" 0 "$STATUS"
assert_not_contains "update on a TTY: no missing banner file" "$OUTPUT" "No such file"
assert_contains "update on a TTY: shows the mark's logo" "$OUTPUT" "$(head -n1 "$HASEEN_PATH/branding/logo-kufic.txt")"
assert_contains "update on a TTY: reaches pacman" "$OUTPUT" "RAN: sudo pacman -Syu"
assert_contains "update on a TTY: reaches the AUR" "$OUTPUT" "RAN: paru -Sua"

capture haseen time sync --dry-run
all+="$OUTPUT"
assert_contains "time sync: ntp" "$OUTPUT" "DRYRUN: sudo timedatectl set-ntp true"
assert_contains "time sync: restart" "$OUTPUT" "DRYRUN: sudo systemctl restart systemd-timesyncd.service"
capture haseen time timezone Europe/Berlin --dry-run
all+="$OUTPUT"
assert_contains "timezone: set" "$OUTPUT" "DRYRUN: sudo timedatectl set-timezone Europe/Berlin"
capture haseen time timezone ../../etc/passwd --dry-run
assert_status "timezone: path climb refused" 1 "$STATUS"
capture haseen time timezone Mars/Olympus --dry-run
assert_status "timezone: unknown refused" 1 "$STATUS"
capture haseen time timezone --dry-run
all+="$OUTPUT"
assert_contains "timezone: picker plan" "$OUTPUT" "timedatectl list-timezones' with fzf"

capture haseen password user --dry-run
all+="$OUTPUT"
assert_contains "password user" "$OUTPUT" "DRYRUN: passwd"

printf 'i2c_hid_acpi 16384 0 - Live 0x0\nhid_multitouch 36864 0 - Live 0x0\n' >"$ROOT/proc/modules"
for t in audio wifi bluetooth trackpad shell; do
    capture haseen restart "$t" --dry-run
    assert_status "restart $t: exit" 0 "$STATUS"
    all+="$OUTPUT"
done
capture haseen restart audio --dry-run
assert_contains "restart audio" "$OUTPUT" "DRYRUN: systemctl --user restart pipewire.service pipewire-pulse.service wireplumber.service"
capture haseen restart trackpad --dry-run
assert_contains "restart trackpad: unload" "$OUTPUT" "DRYRUN: sudo modprobe -r i2c_hid_acpi"
assert_contains "restart trackpad: reload" "$OUTPUT" "DRYRUN: sudo modprobe i2c_hid_acpi"
capture haseen restart bluetooth --dry-run
assert_contains "restart bluetooth" "$OUTPUT" "DRYRUN: sudo systemctl restart bluetooth.service"
capture haseen restart wifi --dry-run
assert_contains "restart wifi" "$OUTPUT" "DRYRUN: nmcli radio wifi on"

mkdir -p "$HOME/.config/hypr"
echo '-- mine' >"$HOME/.config/hypr/hyprland.lua"
capture haseen refresh hyprland --dry-run
all+="$OUTPUT"
assert_contains "refresh hyprland: backup first" "$OUTPUT" "DRYRUN: cp -a -- $HOME/.config/hypr/hyprland.lua $HOME/.config/hypr/hyprland.lua.bak."
assert_contains "refresh hyprland: default copied" "$OUTPUT" "DRYRUN: install -Dm644 -- $HASEEN_PATH/default/hypr/user/hyprland.lua $HOME/.config/hypr/hyprland.lua"
assert_eq "refresh hyprland: dry-run left the file" "-- mine" "$(<"$HOME/.config/hypr/hyprland.lua")"
capture haseen refresh shell --dry-run
all+="$OUTPUT"
assert_contains "refresh shell: seeded when missing" "$OUTPUT" "DRYRUN: install -Dm644 -- $HASEEN_PATH/layers/shell/files/shell.json $HOME/.config/haseen/shell.json"
assert_dry_pure "update/time/password/restart/refresh" "$all"

# refresh for real (user files only, scratch HOME): backup holds the old file.
capture haseen refresh hyprland --yes
assert_status "refresh hyprland: exit" 0 "$STATUS"
assert_eq "refresh hyprland: default in place" "$(<"$HASEEN_PATH/default/hypr/user/hyprland.lua")" "$(<"$HOME/.config/hypr/hyprland.lua")"
bak=("$HOME"/.config/hypr/hyprland.lua.bak.*)
assert_eq "refresh hyprland: backup kept" "-- mine" "$(<"${bak[0]}")"
mkdir -p "$HOME/.config/haseen"
printf '{"bar":{"position":"left"},"plugins":{"haseen.nightlight":{"enabled":true,"settings":{"temperature":3000}}}}\n' >"$HOME/.config/haseen/shell.json"
capture haseen refresh nightlight --dry-run
assert_dry_pure "refresh nightlight" "$OUTPUT"
assert_contains "refresh nightlight: ipc planned" "$OUTPUT" "shell ipc nightlight refresh"
capture haseen refresh nightlight --yes
assert_eq "refresh nightlight: settings dropped, rest kept" '{"bar":{"position":"left"},"plugins":{"haseen.nightlight":{"enabled":true}}}' "$(jq -c . "$HOME/.config/haseen/shell.json")"
bak=("$HOME"/.config/haseen/shell.json.bak.*)
assert_contains "refresh nightlight: backup kept" "$(<"${bak[0]}")" '"temperature":3000'

# --- password drive: LUKS detection and the typed confirmation ---------------
luks_dm() { # DM NAME UUID [SLAVE...]
    local d="$ROOT/sys/block/$1" s
    mkdir -p "$d/dm" "$d/slaves"
    echo "$2" >"$d/dm/name"
    echo "$3" >"$d/dm/uuid"
    shift 3
    for s in "$@"; do mkdir -p "$d/slaves/$s"; done
}
mountinfo() { printf '22 1 0:26 /@ / rw,relatime shared:1 - btrfs %s rw,subvol=/@\n' "$1" >"$ROOT/proc/self/mountinfo"; }

luks_dm dm-0 luks-root CRYPT-LUKS2-0123abcd-luks-root nvme0n1p2
mountinfo /dev/mapper/luks-root
capture haseen password drive --dry-run
assert_status "drive: dry-run exit" 0 "$STATUS"
assert_dry_pure "drive" "$OUTPUT"
assert_contains "drive: warning shown" "$OUTPUT" "the data"
assert_contains "drive: root LUKS partition" "$OUTPUT" "DRYRUN: sudo cryptsetup luksChangeKey --verify-passphrase --pbkdf argon2id /dev/nvme0n1p2"

# The gate: no dry-run, prompts read from a pipe (HASEEN_INLINE skips the
# terminal). A wrong word, an empty answer and --yes all refuse before any
# privileged binary runs.
capture env HASEEN_INLINE=1 bash -c 'echo change | haseen password drive'
assert_status "drive: wrong word refused" 1 "$STATUS"
assert_contains "drive: refusal message" "$OUTPUT" "not confirmed; nothing was changed"
assert_not_contains "drive: nothing ran on refusal" "$OUTPUT" "STUB-CALLED"
capture env HASEEN_INLINE=1 bash -c 'haseen password drive --yes </dev/null'
assert_status "drive: --yes does not bypass" 1 "$STATUS"
assert_not_contains "drive: nothing ran with --yes" "$OUTPUT" "STUB-CALLED"
capture env HASEEN_INLINE=1 bash -c 'echo CHANGE | haseen password drive'
assert_contains "drive: typed word reaches cryptsetup" "$OUTPUT" "STUB-CALLED: sudo cryptsetup luksChangeKey --verify-passphrase --pbkdf argon2id /dev/nvme0n1p2"

# LVM on LUKS1: follow dm slaves down to the crypt mapping.
rm -rf "$ROOT/sys/block"
luks_dm dm-0 cryptlvm CRYPT-LUKS1-89ef-cryptlvm sda2
luks_dm dm-1 vg-root LVM-abcdef dm-0
mountinfo /dev/mapper/vg-root
capture haseen password drive --dry-run
assert_contains "drive: LVM on LUKS1, no argon2" "$OUTPUT" "DRYRUN: sudo cryptsetup luksChangeKey --verify-passphrase /dev/sda2"
mountinfo /dev/nvme0n1p3
capture haseen password drive --dry-run
assert_status "drive: plain root refused" 1 "$STATUS"
assert_contains "drive: plain root message" "$OUTPUT" "no disk encryption"

# --- flatpak layer -------------------------------------------------------------
sandbox catalog-layer
cat_root
capture haseen layer apply flatpak --dry-run
assert_status "layer flatpak: exit" 0 "$STATUS"
assert_dry_pure "layer flatpak" "$OUTPUT"
assert_contains "layer flatpak: order" "$OUTPUT" "apply order: base chaotic desktop flatpak"
assert_contains "layer flatpak: package" "$OUTPUT" "DRYRUN: sudo pacman -S --needed flatpak"
assert_contains "layer flatpak: user remote" "$OUTPUT" "DRYRUN: flatpak remote-add --user --if-not-exists flathub"
capture haseen layer status flatpak
assert_contains "layer flatpak: status names the remote" "$OUTPUT" "Flathub remote"

# --- floating terminal re-exec ------------------------------------------------
stub foot 'echo "FOOT $*"'
capture env -u HASEEN_INLINE bash -c 'haseen time sync </dev/null'
assert_contains "terminal: re-exec in foot with the floating app-id" "$OUTPUT" "FOOT --app-id=haseen.floating --title=haseen -e bash -c"
assert_contains "terminal: runs the same command" "$OUTPUT" "$REPO/bin/haseen-time sync"
assert_not_contains "terminal: nothing ran outside it" "$OUTPUT" "STUB-CALLED"
stub kitty 'echo "KITTY $*"'
capture env -u HASEEN_INLINE TERMINAL=kitty bash -c 'haseen password user </dev/null'
assert_contains "terminal: \$TERMINAL honoured" "$OUTPUT" "KITTY --class=haseen.floating"
capture env -u HASEEN_INLINE bash -c 'haseen install app --installed </dev/null'
assert_not_contains "terminal: read-only queries stay inline" "$OUTPUT" "FOOT"
