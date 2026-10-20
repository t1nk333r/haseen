# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen's answers to Omarchy's omarchy-install-*, omarchy-installed-* and
# omarchy-launch-* commands (plan 093, group g3). Installers: --dry-run runs
# nothing (assert_dry_pure) and packages come through haseen install in the
# repos, Chaotic-AUR, [omarchy], AUR order. Launchers: the argv they start,
# read from recording stubs of setsid and the launched programs.

OMA="$HASEEN_PATH/omarchy"
# The installers open a floating terminal without a TTY; tests run inline.
export HASEEN_INLINE=1
unset OMARCHY_PATH TERMINAL EDITOR BROWSER

# setup NAME — a sandbox with a fixture root (ROOT: pacman with [core],
# [extra] and [multilib]), a call log (LOG), a haseen tree (FAKE) whose bin/
# holds recording stubs of haseen's commands, and chromium as the default
# browser. setsid records the launch it was handed and starts nothing.
setup() {
    sandbox "$1"
    ROOT="$SANDBOX/root"
    LOG="$SANDBOX/calls"
    FAKE="$SANDBOX/fake"
    GPUS=""
    mkdir -p "$ROOT/var/lib/pacman/local" "$ROOT/var/lib/pacman/sync" "$ROOT/etc" \
        "$FAKE/bin" "$FAKE/share/haseen" "$SANDBOX/xdg-data" "$SANDBOX/xdg-config"
    : >"$LOG"
    local d c
    for d in lib layers omarchy default; do
        ln -s "$HASEEN_PATH/$d" "$FAKE/share/haseen/$d"
    done
    for c in haseen-install haseen-webapp-install haseen-layer-apply haseen-setup-default \
        haseen-font-set haseen-config-terminal haseen-screensaver haseen-notification-send; do
        rec "$c"
    done
    repos core extra multilib
    recstub setsid
    # The session's own handler settings never answer here; browser sets
    # the default browser's.
    stub xdg-mime 'exit 1'
    stub gtk-update-icon-cache 'exit 0'
    stub update-desktop-database 'exit 0'
    stub tailscale 'exit 1'
    stub mise 'echo "STUB-CALLED: mise $*" >&2; exit 97'
    export XDG_DATA_DIRS="$SANDBOX/xdg-data" XDG_CONFIG_DIRS="$SANDBOX/xdg-config"
    browser chromium.desktop chromium
}

# argv_log NAME — the bracketed "NAME [arg]..." line a recording stub writes.
argv_log() {
    printf '{ printf %%s "%s"; for a in "$@"; do printf " [%%s]" "$a"; done; echo; } >>"%s"' "$1" "$LOG"
}

# rec NAME [SH] — a fake haseen command that logs its argv, then runs SH.
rec() {
    printf '#!/bin/sh\n%s\n%s\n' "$(argv_log "$1")" "${2:-}" >"$FAKE/bin/$1"
    chmod +x "$FAKE/bin/$1"
}

# recstub NAME [SH] — a PATH stub that logs its argv, then runs SH.
recstub() { stub "$1" "$(argv_log "$1")"$'\n'"${2:-}"; }

# repos NAME... — pacman.conf enables these repositories; pkgs REPO NAME...
# lists packages in one.
repos() {
    local r
    printf '[options]\n' >"$ROOT/etc/pacman.conf"
    for r in "$@"; do
        printf '[%s]\nInclude = /etc/pacman.d/mirrorlist\n' "$r" >>"$ROOT/etc/pacman.conf"
        [[ -e $ROOT/var/lib/pacman/sync/$r.pkgs ]] || : >"$ROOT/var/lib/pacman/sync/$r.pkgs"
    done
}
pkgs() {
    local r=$1
    shift
    printf '%s\n' "$@" >>"$ROOT/var/lib/pacman/sync/$r.pkgs"
}

# mkpkg NAME — an installed package in the fixture's pacman database.
mkpkg() {
    mkdir -p "$ROOT/var/lib/pacman/local/$1-1.0-1"
    printf '%%NAME%%\n%s\n\n%%VERSION%%\n1.0-1\n\n' "$1" >"$ROOT/var/lib/pacman/local/$1-1.0-1/desc"
}

# gpu VENDOR — a PCI display controller (0x1002 AMD, 0x10de NVIDIA).
gpu() {
    local d="$ROOT/sys/bus/pci/devices/0000:0${#GPUS}:00.0"
    GPUS+=x
    mkdir -p "$d"
    echo 0x030000 >"$d/class"
    echo "$1" >"$d/vendor"
    echo 0x1234 >"$d/device"
}

# browser ID BINARY — the default web browser, with its entry and a recording
# BINARY on PATH.
browser() {
    mkdir -p "$XDG_DATA_HOME/applications" "$XDG_CONFIG_HOME"
    printf '[Desktop Entry]\nType=Application\nName=%s\nExec=%s %%U\n' "$2" "$2" >"$XDG_DATA_HOME/applications/$1"
    printf '[Default Applications]\nx-scheme-handler/http=%s\nx-scheme-handler/https=%s\n' "$1" "$1" >"$XDG_CONFIG_HOME/mimeapps.list"
    stub xdg-settings "[ \"\$1\" = get ] && echo $1"
    recstub "$2"
}

# oma NAME ARGS — the command against the real tree; fake NAME ARGS — against
# FAKE's recording stubs. Both read ROOT.
oma() { env HASEEN_SYSROOT="$ROOT" "$OMA/bin/$1" "${@:2}"; }
fake() { env HASEEN_PATH="$FAKE/share/haseen" HASEEN_SYSROOT="$ROOT" "$OMA/bin/$1" "${@:2}"; }
calls() { cat "$LOG"; }

# --- dry-run purity: every installer of the group --------------------------
setup omarchy-launch-dry
gpu 0x1002
DRY_CASES=(
    "omarchy-install-and-launch|Obsidian|obsidian|md.obsidian.Obsidian.desktop"
    "omarchy-install-app|Obsidian|obsidian"
    "omarchy-install-browser|chrome"
    "omarchy-install-dev-env|node"
    "omarchy-install-docker-dbs|postgresql"
    "omarchy-install-font|JetBrains Mono|ttf-jetbrains-mono-nerd|JetBrainsMono Nerd Font"
    "omarchy-install-service-once"
    "omarchy-install-service-tailscale"
    "omarchy-install-terminal|foot"
    "omarchy-install-ai-hermes"
    "omarchy-install-ai-openclaw"
    "omarchy-install-gaming-battlenet"
    "omarchy-install-gaming-geforce-now"
    "omarchy-install-gaming-gpu-lib32"
    "omarchy-install-gaming-xbox-cloud"
    "omarchy-install-hermes-cli|--now"
    "omarchy-install-openclaw-cli|--now"
    "omarchy-install-service-sunshine"
)
for case in "${DRY_CASES[@]}"; do
    IFS='|' read -ra words <<<"$case"
    capture oma "${words[@]}" --dry-run
    assert_status "${words[0]} --dry-run succeeds" 0 "$STATUS"
    assert_dry_pure "${words[0]}" "$OUTPUT"
    assert_contains "${words[0]} --dry-run prints a plan" "$OUTPUT" "DRYRUN:"
done
assert_eq "no dry run wrote a launcher" "chromium.desktop" "$(ls -A "$XDG_DATA_HOME/applications")"

# --- package sources: repos, Chaotic-AUR, [omarchy], then the AUR ----------
setup omarchy-launch-order
repos core extra multilib chaotic-aur omarchy
pkgs chaotic-aur sunshine
pkgs omarchy sunshine
capture oma omarchy-install-service-sunshine --dry-run
assert_contains "sunshine: Chaotic-AUR before [omarchy]" "$OUTPUT" "DRYRUN: sudo pacman -S --needed chaotic-aur/sunshine"
assert_not_contains "sunshine: not from [omarchy] when Chaotic-AUR has it" "$OUTPUT" "omarchy/sunshine"
assert_not_contains "sunshine: no AUR build when a repo has it" "$OUTPUT" "paru -S"
repos core extra multilib omarchy
capture oma omarchy-install-service-sunshine --dry-run
assert_contains "sunshine: [omarchy] before the AUR" "$OUTPUT" "DRYRUN: sudo pacman -S --needed omarchy/sunshine"
repos core extra multilib
capture oma omarchy-install-service-sunshine --dry-run
assert_contains "sunshine: the AUR only as the last resort" "$OUTPUT" "DRYRUN: paru -S --needed sunshine"
repos core extra multilib chaotic-aur omarchy
pkgs extra sunshine
capture oma omarchy-install-service-sunshine --dry-run
assert_contains "sunshine: an official repo first" "$OUTPUT" "DRYRUN: sudo pacman -S --needed sunshine"
assert_not_contains "sunshine: official repo, not Chaotic-AUR" "$OUTPUT" "chaotic-aur/sunshine"

setup omarchy-launch-deny
repos core extra multilib chaotic-aur
pkgs chaotic-aur umu-launcher
printf 'omarchy-settings\nomarchy\n' >"$ROOT/var/lib/pacman/sync/umu-launcher.deps"
capture oma omarchy-install-gaming-battlenet --dry-run --yes
assert_status "battlenet: --yes never accepts omarchy in a closure" 1 "$STATUS"
assert_contains "battlenet: the refusal names the omarchy packages" "$OUTPUT" "would bring in omarchy packages"
assert_not_contains "battlenet: nothing installed after the refusal" "$OUTPUT" "pacman -S --needed chaotic-aur/umu-launcher"

# gpu-lib32: the gaming layer's driver list, matched to the GPUs present.
setup omarchy-launch-lib32
gpu 0x1002
capture oma omarchy-install-gaming-gpu-lib32 --dry-run
assert_status "gpu-lib32: AMD succeeds" 0 "$STATUS"
assert_contains "gpu-lib32: AMD gets mesa and radeon from the repos" "$OUTPUT" \
    "DRYRUN: sudo pacman -S --needed lib32-mesa lib32-vulkan-radeon"
setup omarchy-launch-lib32-nvidia
repos core extra multilib chaotic-aur
pkgs chaotic-aur lib32-nvidia-580xx-utils
gpu 0x10de
mkpkg nvidia-580xx-utils
capture oma omarchy-install-gaming-gpu-lib32 --dry-run
assert_contains "gpu-lib32: a legacy NVIDIA branch's lib32 package, Chaotic-AUR before the AUR" "$OUTPUT" \
    "DRYRUN: sudo pacman -S --needed chaotic-aur/lib32-nvidia-580xx-utils"
assert_dry_pure "gpu-lib32 nvidia" "$OUTPUT"
repos core extra
capture oma omarchy-install-gaming-gpu-lib32 --dry-run
assert_status "gpu-lib32: no [multilib] fails" 1 "$STATUS"
assert_contains "gpu-lib32: says how to enable [multilib]" "$OUTPUT" "uncomment [multilib]"
setup omarchy-launch-lib32-none
capture oma omarchy-install-gaming-gpu-lib32 --dry-run
assert_status "gpu-lib32: no GPU needs nothing" 0 "$STATUS"
assert_contains "gpu-lib32: says so" "$OUTPUT" "no GPU here needs 32-bit drivers"

# --- installers through haseen's commands ----------------------------------
setup omarchy-launch-installers
capture fake omarchy-install-app "Obsidian" "obsidian not-in-catalogue"
assert_contains "install-app: a catalogue word through haseen install app" "$(calls)" "haseen-install [app] [obsidian]"
assert_contains "install-app: the rest through haseen install aur" "$(calls)" "haseen-install [aur] [not-in-catalogue]"
: >"$LOG"
capture fake omarchy-install-terminal foot
assert_eq "install-terminal: install, then make it the default" \
    "haseen-install [app] [foot]"$'\n'"haseen-setup-default [terminal] [foot]" "$(calls)"
: >"$LOG"
capture fake omarchy-install-browser zen
assert_eq "install-browser: the catalogue browser" "haseen-install [app] [zen]" "$(calls)"
: >"$LOG"
capture fake omarchy-install-dev-env node
assert_contains "install-dev-env: haseen install dev" "$(calls)" "haseen-install [dev] [node]"
: >"$LOG"
capture fake omarchy-install-docker-dbs PostgreSQL
assert_contains "install-docker-dbs: the catalogue container" "$(calls)" "haseen-install [app] [postgresql]"
: >"$LOG"
capture fake omarchy-install-font "JetBrains Mono" ttf-jetbrains-mono-nerd "JetBrainsMono Nerd Font"
assert_contains "install-font: haseen install font" "$(calls)" "haseen-install [font]"
: >"$LOG"
capture fake omarchy-install-and-launch Obsidian obsidian md.obsidian.Obsidian.desktop --dry-run
assert_contains "install-and-launch: haseen install app" "$(calls)" "haseen-install [app] [obsidian] [--dry-run]"
assert_contains "install-and-launch: then starts the Flatpak" "$OUTPUT" "DRYRUN: setsid -f flatpak run md.obsidian.Obsidian"
: >"$LOG"
capture fake omarchy-install-gaming-xbox-cloud --dry-run
assert_eq "xbox-cloud: Omarchy's name, URL and icon through haseen webapp install" \
    "haseen-webapp-install [Xbox Cloud Gaming] [https://www.xbox.com/en-US/play] [https://cdn.jsdelivr.net/gh/homarr-labs/dashboard-icons/png/xbox.png] [--dry-run]" "$(calls)"
assert_contains "xbox-cloud: then opens it as a web app" "$OUTPUT" "DRYRUN: setsid chromium --app=https://www.xbox.com/en-US/play"

# battlenet: umu-launcher and lib32 drivers, Blizzard's installer in the prefix.
setup omarchy-launch-battlenet
capture fake omarchy-install-gaming-battlenet --dry-run
assert_status "battlenet --dry-run succeeds" 0 "$STATUS"
assert_contains "battlenet: umu-launcher through haseen install aur" "$(calls)" "haseen-install [aur] [umu-launcher] [--dry-run]"
assert_contains "battlenet: the lib32 drivers step runs" "$OUTPUT" "Installing lib32 graphics drivers"
assert_contains "battlenet: the installer is cached under haseen's cache" "$OUTPUT" \
    "--output $XDG_CACHE_HOME/haseen/Battle.net-Setup.exe"
assert_contains "battlenet: the installer runs in the prefix under GE-Proton" "$OUTPUT" \
    "DRYRUN: env WINEPREFIX=$HOME/Games/battlenet PROTONPATH=GE-Proton GAMEID=umu-battlenet PROTON_VERB=run setsid -f sh -c"
assert_contains "battlenet: the launcher entry runs haseen's launcher" "$OUTPUT" \
    "Exec=\"$OMA/bin/omarchy-launch-battlenet\""
assert_not_contains "battlenet: no fixed /tmp log" "$OUTPUT" "/tmp/omarchy-battlenet"
mkdir -p "$HOME/Games/battlenet/drive_c"
capture fake omarchy-install-gaming-battlenet --dry-run
assert_contains "battlenet: a partial prefix is wiped first" "$OUTPUT" "DRYRUN: rm -rf -- $HOME/Games/battlenet"
mkdir -p "$HOME/Games/battlenet/drive_c/Program Files (x86)/Battle.net"
: >"$HOME/Games/battlenet/drive_c/Program Files (x86)/Battle.net/Battle.net Launcher.exe"
capture fake omarchy-install-gaming-battlenet --dry-run
assert_contains "battlenet: an installed client is kept" "$OUTPUT" "Battle.net is already installed"
assert_not_contains "battlenet: nothing downloaded again" "$OUTPUT" "curl"
assert_not_contains "battlenet: nothing wiped" "$OUTPUT" "rm -rf"

# geforce-now: NVIDIA's Flatpak repository, never its downloaded installer.
setup omarchy-launch-geforce
capture fake omarchy-install-gaming-geforce-now --dry-run
assert_contains "geforce-now: NVIDIA's flatpak remote, user scope" "$OUTPUT" \
    "DRYRUN: flatpak remote-add --user --if-not-exists GeForceNOW https://international.download.nvidia.com/GFNLinux/flatpak/geforcenow.flatpakrepo"
assert_contains "geforce-now: the app from that remote" "$OUTPUT" "DRYRUN: flatpak install --user GeForceNOW com.nvidia.geforcenow"
assert_contains "geforce-now: then a browser beside it" "$OUTPUT" "DRYRUN: setsid $OMA/bin/omarchy-launch-browser"
assert_not_contains "geforce-now: never runs NVIDIA's downloaded installer" "$OUTPUT" "GeForceNOWSetup.bin"
mkdir -p "$XDG_DATA_HOME/flatpak/app/com.nvidia.geforcenow"
capture fake omarchy-install-gaming-geforce-now --dry-run
assert_contains "geforce-now: an installed app is not installed again" "$OUTPUT" "com.nvidia.geforcenow is already installed"

# sunshine: the user unit, ufw rules only with ufw, the admin web app.
setup omarchy-launch-sunshine
mkdir -p "$ROOT/usr/bin" "$ROOT/sys/class/net/tailscale0"
printf '#!/bin/sh\n' >"$ROOT/usr/bin/ufw"
chmod +x "$ROOT/usr/bin/ufw"
capture fake omarchy-install-service-sunshine --dry-run
assert_status "sunshine --dry-run succeeds" 0 "$STATUS"
assert_contains "sunshine: through haseen install aur" "$(calls)" "haseen-install [aur] [sunshine] [--dry-run]"
assert_contains "sunshine: enables its user unit" "$OUTPUT" "DRYRUN: systemctl --user enable --now sunshine"
assert_contains "sunshine: opens a port to the private LANs" "$OUTPUT" \
    "DRYRUN: sudo ufw allow in proto tcp from 192.168.0.0/16 to any port 47984 comment haseen-sunshine"
assert_contains "sunshine: and to Tailscale" "$OUTPUT" \
    "DRYRUN: sudo ufw allow in on tailscale0 to any port 48010 proto udp comment haseen-sunshine"
assert_eq "sunshine: 36 rules, as Omarchy opens" 36 "$(grep -c 'DRYRUN: sudo ufw allow' <<<"$OUTPUT")"
assert_contains "sunshine: the admin web app ignores its self-signed certificate" "$OUTPUT" \
    "Exec=\"$OMA/bin/omarchy-launch-webapp\" https://localhost:47990 --ignore-certificate-errors"
assert_contains "sunshine: opens the admin page" "$OUTPUT" \
    "DRYRUN: setsid chromium --app=https://localhost:47990 --ignore-certificate-errors"
assert_not_contains "sunshine: never edits Hyprland's autostart" "$OUTPUT" "autostart.lua"
rm -f "$ROOT/usr/bin/ufw"
capture fake omarchy-install-service-sunshine --dry-run
assert_contains "sunshine: without ufw the rules are skipped" "$OUTPUT" "UFW is not installed; skipping"
assert_not_contains "sunshine: no ufw call without ufw" "$OUTPUT" "ufw allow"

# --- hermes ------------------------------------------------------------------
setup omarchy-launch-hermes
capture fake omarchy-install-hermes-cli --check
assert_status "hermes-cli --check: nothing installed answers 1" 1 "$STATUS"
capture fake omarchy-install-hermes-cli
assert_status "hermes-cli: no mode is a usage error (exit 1)" 1 "$STATUS"
assert_contains "hermes-cli: says the modes" "$OUTPUT" "Usage: omarchy-install-hermes-cli <--check|--now|--retire-mise>"
capture fake omarchy-install-hermes-cli --retire-mise
assert_status "hermes-cli --retire-mise: nothing of Omarchy's wrapper, nothing to do" 0 "$STATUS"
capture fake omarchy-install-hermes-cli --now
assert_contains "hermes-cli: the package through haseen install app" "$(calls)" "haseen-install [app] [hermes]"
assert_status "hermes-cli: a package without its installer fails" 1 "$STATUS"
assert_contains "hermes-cli: points at haseen update" "$OUTPUT" "Run 'haseen update', then try again."
mkpkg hermes-desktop
mkdir -p "$ROOT/usr/share/hermes-desktop" "$ROOT/opt/hermes-desktop/resources" "$HOME/.local/bin"
: >"$ROOT/usr/share/hermes-desktop/install.sh"
: >"$ROOT/usr/share/hermes-desktop/runtime.patch"
release=0123456789abcdef0123456789abcdef01234567
printf '{"branch":"main","commit":"%s"}\n' "$release" >"$ROOT/opt/hermes-desktop/resources/install-stamp.json"
printf '#!/bin/sh\necho mine\n' >"$HOME/.local/bin/hermes"
: >"$LOG"
capture fake omarchy-install-hermes-cli --now --dry-run
assert_status "hermes-cli --now --dry-run succeeds" 0 "$STATUS"
assert_dry_pure "hermes-cli --now" "$OUTPUT"
assert_eq "hermes-cli: an installed package is not installed again" "" "$(calls)"
assert_contains "hermes-cli: the user's own hermes is saved first" "$OUTPUT" \
    "DRYRUN: cp -a -- $HOME/.local/bin/hermes $HOME/.local/bin/.hermes-before-desktop.XXXXXX/"
assert_contains "hermes-cli: the runtime from the package's installer at the packaged release" "$OUTPUT" \
    "bash $ROOT/usr/share/hermes-desktop/install.sh --skip-setup --branch main --commit $release --force-commit --dir $HOME/.hermes/hermes-agent"
assert_eq "hermes-cli: the user's hermes is untouched by a plan" "echo mine" "$(sed -n 2p "$HOME/.local/bin/hermes")"
: >"$LOG"
capture fake omarchy-install-ai-hermes --dry-run
assert_status "install-ai-hermes --dry-run succeeds" 0 "$STATUS"
assert_contains "install-ai-hermes: opens Hermes Desktop through uwsm" "$OUTPUT" "DRYRUN: setsid uwsm-app -- /usr/bin/hermes-desktop"

# --- openclaw ----------------------------------------------------------------
setup omarchy-launch-openclaw
# systemctl answers the read-only questions, is-active from flag files;
# anything else is a change and fails as every stub does.
stub systemctl "case \"\$2\" in is-active) [ -e '$SANDBOX/active-'\"\$4\" ] && exit 0; exit 3 ;; is-enabled | show) exit 0 ;; esac
echo \"STUB-CALLED: systemctl \$*\" >&2; exit 97"
capture fake omarchy-install-openclaw-cli --check
assert_status "openclaw-cli --check: nothing installed answers 1" 1 "$STATUS"
capture fake omarchy-install-openclaw-cli
assert_status "openclaw-cli: no mode is a usage error (exit 1)" 1 "$STATUS"
mkdir -p "$HOME/.local/bin"
printf '#!/bin/sh\n' >"$HOME/.local/bin/openclaw"
capture fake omarchy-install-openclaw-cli --now --dry-run
assert_status "openclaw-cli: a command of the user's own refuses with 79" 79 "$STATUS"
assert_contains "openclaw-cli: and says what to move" "$OUTPUT" "is not the OpenClaw haseen set up"
rm -f "$HOME/.local/bin/openclaw"
recstub openclaw
capture fake omarchy-install-openclaw-cli --now --dry-run
assert_status "openclaw-cli: another openclaw on PATH refuses with 79" 79 "$STATUS"
rm -f "$SANDBOX/stubs/openclaw"
: >"$LOG"
capture fake omarchy-install-openclaw-cli --now
assert_contains "openclaw-cli: the package through haseen install app" "$(calls)" "haseen-install [app] [openclaw]"
assert_contains "openclaw-cli: a package without the seed is OpenClaw itself" "$OUTPUT" "OpenClaw runs from its package"
mkpkg openclaw
mkdir -p "$ROOT/usr/share/openclaw" "$XDG_CONFIG_HOME/systemd/user"
: >"$ROOT/usr/share/openclaw/install-cli.sh"
: >"$ROOT/usr/share/openclaw/openclaw.tgz"
printf '[Service]\nExecStart=/usr/bin/node /usr/lib/node_modules/openclaw/dist/index.js gateway --port 18789\n' \
    >"$XDG_CONFIG_HOME/systemd/user/openclaw-gateway.service"
: >"$SANDBOX/active-openclaw-gateway.service"
: >"$LOG"
capture fake omarchy-install-openclaw-cli --now --dry-run
assert_status "openclaw-cli --now --dry-run succeeds" 0 "$STATUS"
assert_dry_pure "openclaw-cli --now" "$OUTPUT"
assert_eq "openclaw-cli: an installed package is not installed again" "" "$(calls)"
assert_contains "openclaw-cli: the old package's running gateway is recorded" "$OUTPUT" \
    "DRYRUN: touch $XDG_STATE_HOME/haseen/openclaw-stopped/gateway"
assert_contains "openclaw-cli: and stopped before the move" "$OUTPUT" "DRYRUN: systemctl --user stop openclaw-gateway.service"
assert_contains "openclaw-cli: the seed's own installer, into ~/.openclaw" "$OUTPUT" \
    "DRYRUN: bash $ROOT/usr/share/openclaw/install-cli.sh --install-method npm --prefix $HOME/.openclaw --version $ROOT/usr/share/openclaw/openclaw.tgz --no-onboard"
rm -f "$SANDBOX/active-openclaw-gateway.service"
mkdir -p "$XDG_STATE_HOME/omarchy/openclaw-stopped"
: >"$XDG_STATE_HOME/omarchy/openclaw-stopped/gateway"
capture fake omarchy-install-openclaw-cli --now --dry-run
assert_contains "openclaw-cli: an interrupted Omarchy run's stopped gateway is taken over" "$OUTPUT" \
    "DRYRUN: touch $XDG_STATE_HOME/haseen/openclaw-stopped/gateway"
assert_not_contains "openclaw-cli: Omarchy's record is only read" "$OUTPUT" "$XDG_STATE_HOME/omarchy/openclaw-stopped/gateway"

# install-ai-openclaw: the Control UI launcher runs haseen's launcher.
setup omarchy-launch-ai-openclaw
capture fake omarchy-install-ai-openclaw --dry-run
assert_status "install-ai-openclaw --dry-run succeeds" 0 "$STATUS"
assert_contains "install-ai-openclaw: through openclaw-cli and haseen install app" "$(calls)" "haseen-install [app] [openclaw] [--dry-run]"
assert_contains "install-ai-openclaw: the web app opens through haseen's launcher" "$OUTPUT" \
    "Exec=\"$OMA/bin/omarchy-launch-openclaw\""
assert_contains "install-ai-openclaw: a first install onboards" "$OUTPUT" "once $HOME/.openclaw/openclaw.json exists"
capture fake omarchy-install-ai-openclaw
assert_status "install-ai-openclaw succeeds" 0 "$STATUS"
assert_contains "install-ai-openclaw: writes the OpenClaw launcher" \
    "$(cat "$XDG_DATA_HOME/applications/OpenClaw.desktop" 2>&1)" "Exec=\"$OMA/bin/omarchy-launch-openclaw\""

# launch-openclaw: setup and onboarding in haseen's floating terminal, then
# the Control UI or the TUI.
setup omarchy-launch-launch-openclaw
stub systemctl "case \"\$2\" in is-enabled) exit 0 ;; esac; echo \"STUB-CALLED: systemctl \$*\" >&2; exit 97"
capture fake omarchy-launch-openclaw
assert_eq "launch-openclaw: onboarding in haseen's floating terminal" \
    "haseen-config-terminal [--] [bash] [-c] [$OMA/bin/omarchy-openclaw-onboard && [[ -f \$HOME/.openclaw/openclaw.json ]] && $OMA/bin/omarchy-launch-openclaw]" "$(calls)"
mkpkg openclaw
: >"$LOG"
capture fake omarchy-launch-openclaw
assert_eq "launch-openclaw: a package without a command is set up first" \
    "haseen-config-terminal [--] [bash] [-c] [$OMA/bin/omarchy-install-openclaw-cli --now && $OMA/bin/omarchy-launch-openclaw]" "$(calls)"
mkdir -p "$HOME/.openclaw"
echo '{}' >"$HOME/.openclaw/openclaw.json"
recstub openclaw "[ \"\$1\" = dashboard ] && echo '{\"browserUrl\":\"http://127.0.0.1:18789/#token=t\"}'; exit 0"
: >"$LOG"
capture fake omarchy-launch-openclaw
assert_contains "launch-openclaw: the Control UI as a web app" "$(calls)" "setsid [chromium] [--app=http://127.0.0.1:18789/#token=t]"
: >"$LOG"
capture fake omarchy-launch-openclaw --tui --message hello
assert_contains "launch-openclaw --tui: attaches to the gateway" "$(calls)" "openclaw [tui] [--message] [hello]"
recstub openclaw "exit 1"
capture fake omarchy-launch-openclaw --dry-run
assert_contains "launch-openclaw: a stopped gateway is started first" "$OUTPUT" "DRYRUN: timeout 60 openclaw gateway start"
assert_dry_pure "launch-openclaw" "$OUTPUT"

# --- launchers -----------------------------------------------------------------
setup omarchy-launch-apps
mkdir -p "$XDG_DATA_HOME/flatpak/app/com.onepassword.OnePassword"
capture fake omarchy-launch-1password
assert_eq "launch-1password: the Flatpak at scale 1" \
    "setsid [flatpak] [run] [com.onepassword.OnePassword] [--force-device-scale-factor=1]" "$(calls)"
: >"$LOG"
recstub discord
capture fake omarchy-launch-discord-community
assert_eq "launch-discord-community: the invite in Discord" \
    "setsid [discord] [--url] [--] [discord://-/invite/tXFUdasqhY]" "$(calls)"
: >"$LOG"
recstub umu-run
launcher="$HOME/Games/battlenet/drive_c/Program Files (x86)/Battle.net/Battle.net Launcher.exe"
mkdir -p "${launcher%/*}"
: >"$launcher"
capture fake omarchy-launch-battlenet
assert_eq "launch-battlenet: umu-run on the prefix's launcher" "umu-run [$launcher]" "$(calls)"
: >"$LOG"
capture env DRY_RUN=true "$OMA/bin/omarchy-launch-browser" --private https://example.org
assert_contains "launch-browser: --private is chromium's incognito" "$OUTPUT" "DRYRUN: setsid -f chromium --incognito https://example.org"
browser zen.desktop zen-browser
capture env DRY_RUN=true "$OMA/bin/omarchy-launch-browser" --private
assert_contains "launch-browser: a Firefox-family private window" "$OUTPUT" "DRYRUN: setsid -f zen-browser --private-window"
browser chromium.desktop chromium
capture env DRY_RUN=true "$OMA/bin/omarchy-launch-webapp" https://example.org --ozone-platform=wayland
assert_contains "launch-webapp: --app= in the chromium-family default" "$OUTPUT" \
    "DRYRUN: setsid chromium --app=https://example.org --ozone-platform=wayland"
recstub lazydocker
mkdir -p "$ROOT/var/run"
capture env DRY_RUN=true HASEEN_PATH="$FAKE/share/haseen" HASEEN_SYSROOT="$ROOT" "$OMA/bin/omarchy-launch-docker-tui"
assert_contains "launch-docker-tui: a socket it cannot write goes through polkit" "$OUTPUT" \
    "DRYRUN: pkexec /usr/bin/env TERM="
capture env HASEEN_PATH="$FAKE/share/haseen" HASEEN_SYSROOT="$ROOT" "$OMA/bin/omarchy-launch-docker-tui" --dry-run
assert_contains "launch-docker-tui: --dry-run prints the polkit command" "$OUTPUT" "DRYRUN: pkexec"
: >"$ROOT/var/run/docker.sock"
: >"$LOG"
capture fake omarchy-launch-docker-tui
assert_eq "launch-docker-tui: a writable socket runs lazydocker as the user" "lazydocker" "$(calls)"
: >"$LOG"
recstub nvim
recstub foot
capture env EDITOR=nvim "$OMA/bin/omarchy-launch-editor" "$HOME/notes.md"
assert_eq "launch-editor: a terminal editor opens in a TUI window" \
    "setsid [foot] [--app-id=org.omarchy.nvim] [-e] [nvim] [--] [$HOME/notes.md]" "$(calls)"
: >"$LOG"
capture env EDITOR=nvim "$OMA/bin/omarchy-launch-editor" --inline "$HOME/notes.md"
assert_eq "launch-editor --inline: runs in place" "nvim [--] [$HOME/notes.md]" "$(calls)"
: >"$LOG"
stub xdg-mime '[ "$3" = inode/directory ] && echo haseen-yazi.desktop'
capture fake omarchy-launch-nautilus
assert_eq "launch-nautilus: home in the folder handler" "setsid [gtk-launch] [haseen-yazi.desktop] [$HOME]" "$(calls)"
: >"$LOG"
capture fake omarchy-launch-nautilus-cwd
assert_eq "launch-nautilus-cwd: without a terminal, home" "setsid [gtk-launch] [haseen-yazi.desktop] [$HOME]" "$(calls)"

setup omarchy-launch-terminals
recstub foot
capture fake omarchy-launch-terminal
assert_eq "launch-terminal: foot in the working directory" "setsid [foot] [--working-directory=$HOME]" "$(calls)"
: >"$LOG"
capture fake omarchy-launch-terminal-tmux
assert_eq "launch-terminal-tmux: attach or start the Work session" \
    "setsid [foot] [--working-directory=$HOME] [-e] [bash] [-c] [tmux attach || tmux new -s Work]" "$(calls)"
: >"$LOG"
recstub herdr
capture fake omarchy-launch-terminal-herdr
assert_eq "launch-terminal-herdr: a terminal running herdr" \
    "setsid [foot] [--working-directory=$HOME] [-e] [herdr]" "$(calls)"
: >"$LOG"
capture fake omarchy-launch-tui btop
assert_eq "launch-tui: Omarchy's app-id for the command" "setsid [foot] [--app-id=org.omarchy.btop] [-e] [btop]" "$(calls)"
: >"$LOG"
capture fake omarchy-launch-tui --app-id=my.id htop -d 10
assert_eq "launch-tui: a given app-id and arguments" "setsid [foot] [--app-id=my.id] [-e] [htop] [-d] [10]" "$(calls)"
: >"$LOG"
capture fake omarchy-launch-or-focus "signal" "uwsm-app -- signal-desktop --start-in-tray"
assert_eq "launch-or-focus: no window, so the launch command, without uwsm outside a session" \
    "setsid [signal-desktop] [--start-in-tray]" "$(calls)"
capture fake omarchy-launch-or-focus
assert_status "launch-or-focus: no pattern is a usage error" 1 "$STATUS"
: >"$LOG"
capture fake omarchy-launch-or-focus-tui btop
assert_eq "launch-or-focus-tui: launches through omarchy-launch-tui" \
    "setsid [$OMA/bin/omarchy-launch-tui] [--app-id=org.omarchy.btop] [btop]" "$(calls)"
: >"$LOG"
capture fake omarchy-launch-or-focus-webapp YouTube https://youtube.com
assert_eq "launch-or-focus-webapp: launches through omarchy-launch-webapp" \
    "setsid [$OMA/bin/omarchy-launch-webapp] [https://youtube.com]" "$(calls)"
: >"$LOG"
mkdir -p "$XDG_DATA_HOME/flatpak/app/org.signal.Signal" "$XDG_DATA_HOME/flatpak/app/com.spotify.Client"
capture fake omarchy-launch-signal
assert_eq "launch-signal: the Flatpak" "setsid [flatpak] [run] [org.signal.Signal]" "$(calls)"
: >"$LOG"
capture fake omarchy-launch-spotify
assert_eq "launch-spotify: the Flatpak" "setsid [flatpak] [run] [com.spotify.Client]" "$(calls)"
: >"$LOG"
capture fake omarchy-launch-floating-terminal-with-presentation 'echo hi'
assert_eq "launch-floating-terminal-with-presentation: haseen's floating terminal" \
    "haseen-config-terminal [--] [bash] [-c] [echo hi]" "$(calls)"
: >"$LOG"
capture fake omarchy-launch-screensaver force
assert_eq "launch-screensaver force: haseen screensaver --force" "haseen-screensaver [--force]" "$(calls)"

# installed-service probes: exit codes only, nothing printed.
capture fake omarchy-installed-service-dropbox
assert_status "installed-service-dropbox: not running answers 1" 1 "$STATUS"
recstub dropbox-cli
capture fake omarchy-installed-service-dropbox
assert_status "installed-service-dropbox: dropbox-cli running answers 0" 0 "$STATUS"
assert_eq "installed-service-dropbox: prints nothing" "" "$OUTPUT"
capture fake omarchy-installed-service-tailscale
assert_status "installed-service-tailscale: no tailscaled answers 1" 1 "$STATUS"
mkdir -p "$ROOT/etc/systemd/system/multi-user.target.wants"
: >"$ROOT/etc/systemd/system/multi-user.target.wants/tailscaled.service"
capture fake omarchy-installed-service-tailscale
assert_status "installed-service-tailscale: an enabled tailscaled answers 0" 0 "$STATUS"
