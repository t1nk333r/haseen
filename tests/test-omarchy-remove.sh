# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen's answers to Omarchy's omarchy-remove-* commands (plan 093, group g4b).
# Removals go through haseen remove, deletions through run, questions through
# remove-lib.sh's ask: default no; --yes never deletes the user's data (games,
# saves, toolchains, configs): that takes a yes at a terminal or --purge.

OMA="$HASEEN_PATH/omarchy"
# The commands open a floating terminal without a TTY; tests answer on stdin.
export HASEEN_INLINE=1
unset OMARCHY_PATH OMARCHY_DEFER_REBOOT

# setup NAME — a sandbox with a fixture root (ROOT), a call log (LOG) and a
# haseen tree (FAKE) whose bin/ holds recording stubs of haseen's commands.
setup() {
    sandbox "$1"
    ROOT="$SANDBOX/root"
    LOG="$SANDBOX/calls"
    FAKE="$SANDBOX/fake"
    mkdir -p "$ROOT/var/lib/pacman/local" "$ROOT/etc/pam.d" "$FAKE/bin" "$FAKE/share/haseen"
    : >"$LOG"
    ln -s "$HASEEN_PATH/lib" "$FAKE/share/haseen/lib"
    ln -s "$HASEEN_PATH/omarchy" "$FAKE/share/haseen/omarchy"
    local c
    for c in haseen-remove haseen-webapp-remove haseen-plugin-disable haseen-setup-default haseen-system \
        haseen-notification-send; do
        rec "$c"
    done
}

# rec NAME [SH] — a fake haseen command that logs "NAME [arg]..." then runs SH.
rec() {
    printf '#!/bin/sh\n{ printf %%s "${0##*/}"; for a in "$@"; do printf " [%%s]" "$a"; done; echo; } >>"%s"\n%s\n' \
        "$LOG" "${2:-}" >"$FAKE/bin/$1"
    chmod +x "$FAKE/bin/$1"
}

# mkpkg NAME [DEP...] — an installed package in the fixture's pacman database.
mkpkg() {
    local name=$1 d
    shift
    d="$ROOT/var/lib/pacman/local/$name-1.0-1"
    mkdir -p "$d"
    {
        printf '%%NAME%%\n%s\n\n%%VERSION%%\n1.0-1\n\n' "$name"
        if (($#)); then
            printf '%%DEPENDS%%\n'
            printf '%s\n' "$@"
            echo
        fi
    } >"$d/desc"
    printf '%%FILES%%\n' >"$d/files"
}

# recording_sudo — sudo logs its argv and keeps what `tee` was given, running
# nothing: root writes in a non-dry run land in LOG.tee, never in /etc.
recording_sudo() {
    stub sudo "echo \"sudo \$*\" >>'$LOG'; if [ \"\$1\" = tee ]; then cat >>'$LOG.tee'; fi; exit 0"
}

# oma NAME ARGS — the command against the real tree; fake NAME ARGS — against
# FAKE's recording stubs. Both read ROOT.
oma() { env HASEEN_SYSROOT="$ROOT" "$OMA/bin/$1" "${@:2}"; }
fake() { env HASEEN_PATH="$FAKE/share/haseen" HASEEN_SYSROOT="$ROOT" "$OMA/bin/$1" "${@:2}"; }
calls() { cat "$LOG"; }

GROUP=(omarchy-remove-ai-hermes omarchy-remove-ai-openclaw omarchy-remove-ai-perplexity
    omarchy-remove-ai-t3-code omarchy-remove-browser omarchy-remove-dev-env
    omarchy-remove-gaming-battlenet omarchy-remove-gaming-geforce-now omarchy-remove-gaming-heroic
    omarchy-remove-gaming-lutris omarchy-remove-gaming-minecraft omarchy-remove-gaming-retroarch
    omarchy-remove-gaming-steam omarchy-remove-gaming-xbox-cloud omarchy-remove-gaming-xbox-controllers
    omarchy-remove-launcher-entry omarchy-remove-security-fido2 omarchy-remove-security-fingerprint
    omarchy-remove-security-sshd omarchy-remove-security-sudoless-docker omarchy-remove-service-1password
    omarchy-remove-service-dropbox omarchy-remove-service-sunshine omarchy-remove-service-tailscale)

# --- every script: help, notice, purity over an empty machine -------------------
setup omarchy-remove-all
bad="" notice=""
for name in "${GROUP[@]}"; do
    capture oma "$name" --help
    [[ $STATUS == 0 && $OUTPUT == *Usage:* && $OUTPUT != *STUB-CALLED* ]] || bad+="$name($STATUS) "
    # Header comments wrap: compare with the comment marks and line breaks
    # squeezed out, as tests/test-omarchy-commands.sh does.
    tr -s ' \n#' ' ' <"$OMA/bin/$name" | grep -q 'MIT, Copyright (c) David Heinemeier Hansson' || notice+="$name "
done
assert_eq "every remover answers --help without running anything" "" "$bad"
assert_eq "every remover names Omarchy's MIT notice" "" "$notice"
assert_eq "remove-lib.sh is sourced, not run" "644" "$(stat -c %a "$OMA/remove-lib.sh")"
bad=""
for name in "${GROUP[@]}"; do
    args=(--dry-run)
    case $name in
    *-browser) args+=(firefox) ;;
    *-dev-env) args+=(node) ;;
    *-launcher-entry) continue ;;
    esac
    capture oma "$name" "${args[@]}"
    [[ $OUTPUT != *STUB-CALLED* ]] || bad+="$name "
done
assert_eq "every remover's dry run on a bare machine runs nothing" "" "$bad"

# --- the dependency guard ----------------------------------------------------------
setup omarchy-remove-lutris
mkpkg lutris wine-staging python-protobuf winetricks
mkpkg wine-staging
mkpkg winetricks
mkpkg python-protobuf
mkpkg other-app 'python-protobuf>=3'
mkpkg game wine
mkpkg wine-provider
printf '%%PROVIDES%%\nwine\n\n' >>"$ROOT/var/lib/pacman/local/wine-staging-1.0-1/desc"
mkdir -p "$HOME/.wine" "$HOME/.config/lutris" "$HOME/.local/share/flatpak/app/net.lutris.Lutris"
capture oma omarchy-remove-gaming-lutris --dry-run
assert_status "lutris dry run" 0 "$STATUS"
assert_dry_pure "lutris" "$OUTPUT"
assert_contains "lutris: what nothing else needs goes in one pacman -Rns" "$OUTPUT" \
    "DRYRUN: sudo pacman -Rns --noconfirm lutris winetricks"
assert_contains "lutris: a package another needs (by name or what it provides) stays" "$OUTPUT" \
    "kept wine-staging python-protobuf: another installed package needs it"
assert_contains "lutris: the Flatpak goes too" "$OUTPUT" "DRYRUN: flatpak uninstall --user -y net.lutris.Lutris"
assert_contains "lutris: the data question is planned" "$OUTPUT" "DRYRUN: ask 'Also delete the Lutris"
assert_contains "lutris: ~/.wine is in the planned deletion" "$OUTPUT" "$HOME/.wine"
[[ -d $HOME/.wine ]] && _pass || _fail "lutris dry run deleted nothing"

# --- ai -----------------------------------------------------------------------------
setup omarchy-remove-hermes
stub systemctl "echo \"systemctl \$*\" >>'$LOG'; exit 0"
units="$HOME/.config/systemd/user"
mkdir -p "$units" "$HOME/.hermes/hermes-agent" "$HOME/.hermes/node" "$HOME/.hermes/chats" "$HOME/.config/Hermes" "$HOME/.local/bin"
touch "$HOME/.hermes/hermes-agent/.hermes-bootstrap-complete"
printf '[Service]\nExecStart=%s/.hermes/hermes-agent/venv/bin/hermes gateway\n' "$HOME" >"$units/hermes-gateway.service"
printf '[Service]\nExecStart=/opt/elsewhere/hermes gateway\n' >"$units/hermes-gateway-other.service"
printf '#!/bin/sh\nexec %s/.hermes/bin/hermes "$@"\n' "$HOME" >"$HOME/.local/bin/hermes"
printf '#!/bin/sh\nexec /usr/bin/hermes-acp "$@"\n' >"$HOME/.local/bin/hermes-acp"
ln -s "$HOME/.hermes/node/bin/node" "$HOME/.local/bin/node"
mkpkg hermes-desktop
capture fake omarchy-remove-ai-hermes --yes
assert_status "hermes --yes" 0 "$STATUS"
assert_contains "hermes: the package goes through haseen remove" "$(calls)" \
    "haseen-remove [package] [hermes-desktop] [--yes]"
assert_contains "hermes: its gateway unit is disabled" "$(calls)" "systemctl --user disable --now hermes-gateway.service"
[[ ! -e $units/hermes-gateway.service && -e $units/hermes-gateway-other.service ]] && _pass ||
    _fail "hermes: only the unit running its runtime goes"
[[ ! -e $HOME/.hermes/hermes-agent && ! -e $HOME/.local/bin/hermes && ! -L $HOME/.local/bin/node ]] && _pass ||
    _fail "hermes: the marker-proven runtime, its wrapper and its node link go"
[[ -e $HOME/.local/bin/hermes-acp ]] && _pass || _fail "hermes: a wrapper not pointing into ~/.hermes stays"
[[ -d $HOME/.hermes/chats && -d $HOME/.config/Hermes ]] && _pass || _fail "hermes: --yes keeps the chats and tokens"
capture fake omarchy-remove-ai-hermes <<<"y"
[[ ! -e $HOME/.hermes && ! -e $HOME/.config/Hermes ]] && _pass || _fail "hermes: a yes at the terminal deletes the data"

setup omarchy-remove-openclaw
mkdir -p "$HOME/.config/systemd/user" "$HOME/.openclaw/bin" "$HOME/.local/share/applications" "$HOME/.local/bin"
printf '[Service]\n' >"$HOME/.config/systemd/user/openclaw-gateway.service"
ln -s "$HOME/.openclaw/bin/openclaw" "$HOME/.local/bin/openclaw"
printf '[Desktop Entry]\n' >"$HOME/.local/share/applications/OpenClaw.desktop"
mkpkg openclaw
capture oma omarchy-remove-ai-openclaw --dry-run
assert_dry_pure "openclaw" "$OUTPUT"
assert_contains "openclaw: the gateway unit is disabled" "$OUTPUT" "DRYRUN: systemctl --user disable --now openclaw-gateway.service"
assert_contains "openclaw: the package goes" "$OUTPUT" "DRYRUN: sudo pacman -Rns --noconfirm openclaw"
assert_contains "openclaw: the launcher goes" "$OUTPUT" "DRYRUN: rm -f -- $HOME/.local/share/applications/OpenClaw.desktop"
stub systemctl "exit 0"
capture fake omarchy-remove-ai-openclaw --yes
[[ -d $HOME/.openclaw && ! -L $HOME/.local/bin/openclaw && ! -e $HOME/.local/share/applications/OpenClaw.desktop ]] &&
    _pass || _fail "openclaw: --yes removes its link and launcher, keeps ~/.openclaw"

setup omarchy-remove-perplexity
mkdir -p "$HOME/.cache/Perplexity" "$HOME/.local/share/perplexity-rpc-server" "$HOME/.config/Perplexity" "$HOME/.local/state/perplexity"
capture fake omarchy-remove-ai-perplexity --yes
[[ -d $HOME/.cache/Perplexity && -d $HOME/.local/share/perplexity-rpc-server ]] && _pass ||
    _fail "perplexity: --yes alone keeps the runtime caches"
assert_contains "perplexity: --yes says how to delete them" "$OUTPUT" "add --purge"
capture fake omarchy-remove-ai-perplexity --purge --yes
[[ ! -e $HOME/.cache/Perplexity && ! -e $HOME/.local/share/perplexity-rpc-server ]] && _pass ||
    _fail "perplexity: --purge --yes deletes the runtime caches"
[[ -d $HOME/.config/Perplexity && -d $HOME/.local/state/perplexity ]] && _pass ||
    _fail "perplexity: --purge keeps the logins and vault"

setup omarchy-remove-t3code
mkpkg t3code-bin
mkdir -p "$HOME/.config/t3code" "$HOME/.t3/worktrees/repo"
capture fake omarchy-remove-ai-t3-code --yes
assert_contains "t3-code: the package goes through haseen remove" "$(calls)" "haseen-remove [package] [t3code-bin] [--yes]"
[[ -d $HOME/.config/t3code && -d $HOME/.t3/worktrees/repo ]] && _pass ||
    _fail "t3-code: --yes alone keeps the settings and the worktrees"
capture fake omarchy-remove-ai-t3-code --purge --yes
[[ ! -e $HOME/.config/t3code && -d $HOME/.t3/worktrees/repo ]] && _pass ||
    _fail "t3-code: --purge deletes the settings but keeps the worktrees in ~/.t3"
capture fake omarchy-remove-ai-t3-code <<<"y"
[[ ! -e $HOME/.t3 ]] && _pass || _fail "t3-code: a yes at the terminal deletes ~/.t3"

# --- browser and dev environments ----------------------------------------------------
setup omarchy-remove-browser
rec haseen-setup-default '[ $# -eq 1 ] && echo chrome; exit 0'
mkpkg google-chrome
mkpkg helium-browser-bin
mkdir -p "$HOME/.local/share/flatpak/app/com.google.Chrome" "$ROOT/etc/opt/chrome/policies/managed" "$HOME/.config"
touch "$ROOT/etc/opt/chrome/policies/managed/omarchy.json" "$ROOT/etc/opt/chrome/policies/managed/user.json"
printf -- '--ozone-platform=wayland\n' >"$HOME/.config/chrome-flags.conf"
capture fake omarchy-remove-browser chrome --dry-run
assert_status "browser chrome dry run" 0 "$STATUS"
assert_dry_pure "browser" "$OUTPUT"
assert_contains "browser: the default moves to helium" "$(calls)" "haseen-setup-default [browser] [helium] [--dry-run]"
assert_contains "browser: the package goes" "$(calls)" "haseen-remove [package] [google-chrome] [--yes] [--dry-run]"
assert_contains "browser: the Flatpak goes" "$(calls)" "haseen-remove [app] [chrome] [--yes] [--dry-run]"
assert_contains "browser: Omarchy's policy goes" "$OUTPUT" "DRYRUN: sudo rm -f -- /etc/opt/chrome/policies/managed/omarchy.json"
assert_not_contains "browser: other policies stay" "$OUTPUT" "user.json"
assert_contains "browser: the flags file is asked about" "$OUTPUT" "DRYRUN: rm -rf -- $HOME/.config/chrome-flags.conf"
capture fake omarchy-remove-browser opera
assert_status "browser: an unknown name is a usage error" 1 "$STATUS"

setup omarchy-remove-dev
stub mise "echo \"mise \$*\" >>'$LOG'; exit 0"
printf 'gem: --no-document\n' >"$HOME/.gemrc"
capture fake omarchy-remove-dev-env ruby
assert_contains "dev-env: ruby goes through haseen remove dev" "$(calls)" "haseen-remove [dev] [ruby] [--yes]"
[[ ! -e $HOME/.gemrc ]] && _pass || _fail "dev-env: the installer's ~/.gemrc goes"
printf 'gem: --no-document\n:verbose: true\n' >"$HOME/.gemrc"
capture fake omarchy-remove-dev-env ruby
[[ -e $HOME/.gemrc ]] && _pass || _fail "dev-env: a ~/.gemrc with more in it stays"
capture fake omarchy-remove-dev-env clojure
assert_contains "dev-env: clojure drops only clojure (java stays)" "$(calls)" "mise unuse --global clojure"
assert_not_contains "dev-env: clojure keeps java" "$(calls)" "java"
capture fake omarchy-remove-dev-env phoenix
assert_contains "dev-env: phoenix is elixir" "$(calls)" "haseen-remove [dev] [elixir] [--yes]"
mkpkg php
mkpkg composer
capture oma omarchy-remove-dev-env php --dry-run
assert_contains "dev-env: php's packages go" "$OUTPUT" "DRYRUN: sudo pacman -Rns --noconfirm php composer"
assert_dry_pure "dev-env php" "$OUTPUT"
mkdir -p "$HOME/.opam/default"
stub opam "echo \"opam \$*\" >>'$LOG'; exit 0"
capture fake omarchy-remove-dev-env ocaml --yes
[[ -d $HOME/.opam/default ]] && _pass || _fail "dev-env: --yes alone keeps ~/.opam"
assert_not_contains "dev-env: --yes alone keeps opam's default switch" "$(calls)" "opam switch remove"
capture oma omarchy-remove-dev-env ocaml --dry-run --yes
assert_contains "dev-env: a dry run still plans the ~/.opam deletion" "$OUTPUT" "DRYRUN: rm -rf -- $HOME/.opam"
assert_contains "dev-env: and the switch removal before it" "$OUTPUT" "DRYRUN: opam switch remove default -y"
capture fake omarchy-remove-dev-env ocaml --purge --yes
[[ ! -e $HOME/.opam ]] && _pass || _fail "dev-env: --purge --yes deletes ~/.opam"
assert_contains "dev-env: --purge --yes removes opam's default switch" "$(calls)" "opam switch remove default -y"
stub rustup "echo \"rustup \$*\" >>'$LOG'; exit 0"
capture fake omarchy-remove-dev-env rust --yes
assert_not_contains "dev-env: --yes alone never runs rustup self uninstall (~/.cargo)" "$(calls)" "rustup self uninstall"
capture fake omarchy-remove-dev-env rust --yes --purge
assert_contains "dev-env: --purge runs rustup self uninstall" "$(calls)" "rustup self uninstall -y"
capture fake omarchy-remove-dev-env cobol
assert_status "dev-env: an unknown environment fails" 1 "$STATUS"

# --- gaming ---------------------------------------------------------------------
setup omarchy-remove-battlenet
mkpkg umu-launcher
mkdir -p "$HOME/Games/battlenet/drive_c" "$HOME/.local/share/applications" "$HOME/.local/share/Steam/compatibilitytools.d/GE-Proton9"
printf '[Desktop Entry]\n' >"$HOME/.local/share/applications/battlenet.desktop"
capture fake omarchy-remove-gaming-battlenet --yes
assert_status "battlenet --yes" 0 "$STATUS"
[[ -d $HOME/Games/battlenet/drive_c && ! -e $HOME/.local/share/applications/battlenet.desktop ]] && _pass ||
    _fail "battlenet: --yes removes the launcher but keeps the prefix with the games"
capture fake omarchy-remove-gaming-battlenet --purge --yes
[[ ! -e $HOME/Games/battlenet ]] && _pass || _fail "battlenet: --purge --yes deletes the prefix"
[[ -d $HOME/.local/share/Steam/compatibilitytools.d/GE-Proton9 ]] && _pass || _fail "battlenet: --yes keeps GE-Proton"
assert_not_contains "battlenet: --yes keeps umu-launcher" "$(calls)" "umu-launcher"

setup omarchy-remove-geforce
mkdir -p "$HOME/.local/share/flatpak/app/com.nvidia.geforcenow" "$HOME/.var/app/com.nvidia.geforcenow"
capture fake omarchy-remove-gaming-geforce-now
assert_contains "geforce-now: the Flatpak goes through haseen remove" "$(calls)" \
    "haseen-remove [flatpak] [com.nvidia.geforcenow] [--yes]"
[[ -d $HOME/.var/app/com.nvidia.geforcenow ]] && _pass || _fail "geforce-now: no answer keeps the data"
capture fake omarchy-remove-gaming-geforce-now --yes
[[ -d $HOME/.var/app/com.nvidia.geforcenow ]] && _pass || _fail "geforce-now: --yes alone keeps the data"
capture fake omarchy-remove-gaming-geforce-now --purge --yes
[[ ! -e $HOME/.var/app/com.nvidia.geforcenow ]] && _pass || _fail "geforce-now: --purge --yes deletes the data"

setup omarchy-remove-heroic
mkpkg heroic-games-launcher-bin
mkdir -p "$HOME/.config/heroic" "$HOME/Games/Heroic/game"
capture fake omarchy-remove-gaming-heroic <<<"n"
assert_contains "heroic: the package goes" "$(calls)" "haseen-remove [package] [heroic-games-launcher-bin] [--yes]"
assert_not_contains "heroic: no Flatpak, no Flatpak removal" "$(calls)" "[app]"
[[ -d $HOME/Games/Heroic/game ]] && _pass || _fail "heroic: a no keeps the games"
capture fake omarchy-remove-gaming-heroic <<<"y"
[[ ! -e $HOME/Games/Heroic && ! -e $HOME/.config/heroic ]] && _pass || _fail "heroic: a yes deletes the games and configs"

setup omarchy-remove-minecraft
mkdir -p "$HOME/.minecraft/saves" "$HOME/.local/share/flatpak/app/com.mojang.Minecraft"
capture oma omarchy-remove-gaming-minecraft --dry-run
assert_dry_pure "minecraft" "$OUTPUT"
assert_contains "minecraft: the Flatpak goes" "$OUTPUT" "DRYRUN: flatpak uninstall --user -y com.mojang.Minecraft"
assert_contains "minecraft: the worlds are in the planned deletion" "$OUTPUT" "DRYRUN: rm -rf -- $HOME/.minecraft"

setup omarchy-remove-retroarch
mkpkg retroarch
mkpkg libretro-snes9x
mkdir -p "$HOME/.config/retroarch" "$HOME/Games/roms" "$HOME/Games/bios"
capture fake omarchy-remove-gaming-retroarch --yes
assert_contains "retroarch: the installed packages go" "$(calls)" "haseen-remove [package] [retroarch] [libretro-snes9x] [--yes]"
[[ -d $HOME/.config/retroarch ]] && _pass || _fail "retroarch: --yes alone keeps the config and saves"
capture fake omarchy-remove-gaming-retroarch --purge --yes
[[ ! -e $HOME/.config/retroarch && -d $HOME/Games/roms && -d $HOME/Games/bios ]] && _pass ||
    _fail "retroarch: --purge --yes deletes the config, keeps ROMs and BIOS"

setup omarchy-remove-steam
mkpkg steam
mkdir -p "$HOME/.local/share/Steam/steamapps"
capture fake omarchy-remove-gaming-steam
assert_contains "steam: removed through the catalogue entry" "$(calls)" "haseen-remove [app] [steam] [--yes]"
[[ -d $HOME/.local/share/Steam/steamapps ]] && _pass || _fail "steam: no answer keeps the library"
capture fake omarchy-remove-gaming-steam --yes
[[ -d $HOME/.local/share/Steam/steamapps ]] && _pass || _fail "steam: --yes alone keeps the library"
capture oma omarchy-remove-gaming-steam --dry-run --yes
assert_dry_pure "steam" "$OUTPUT"
assert_contains "steam: a dry run under --yes still plans the deletion" "$OUTPUT" "DRYRUN: rm -rf -- $HOME/.local/share/Steam"
assert_contains "steam: the dry run plans the package removal" "$OUTPUT" "DRYRUN: sudo pacman -Rns --noconfirm steam"
capture fake omarchy-remove-gaming-heroic --purge --dry-run
assert_status "heroic: --purge is one of its options" 0 "$STATUS"
capture fake omarchy-remove-ai-hermes --purge
assert_status "hermes: --purge is a usage error (only a terminal answer deletes its data)" 2 "$STATUS"

setup omarchy-remove-xbox-cloud
apps="$HOME/.local/share/applications"
mkdir -p "$apps" "$HOME/.local/share/icons/hicolor/256x256/apps"
printf '[Desktop Entry]\nExec=omarchy-launch-webapp https://www.xbox.com/play\n' >"$apps/Xbox Cloud Gaming.desktop"
touch "$HOME/.local/share/icons/hicolor/256x256/apps/xbox-cloud-gaming.png"
capture oma omarchy-remove-gaming-xbox-cloud --dry-run
assert_dry_pure "xbox-cloud" "$OUTPUT"
assert_contains "xbox-cloud: Omarchy's launcher goes" "$OUTPUT" "DRYRUN: rm -f -- $apps/Xbox Cloud Gaming.desktop"
assert_contains "xbox-cloud: its icon goes" "$OUTPUT" "xbox-cloud-gaming.png"
printf '[Desktop Entry]\nExec=chromium --app=https://www.xbox.com/play\n' >"$apps/Xbox Cloud Gaming.desktop"
capture fake omarchy-remove-gaming-xbox-cloud
assert_contains "xbox-cloud: haseen's web app goes through haseen webapp remove" "$(calls)" \
    "haseen-webapp-remove [Xbox Cloud Gaming]"
rm -f "$apps/Xbox Cloud Gaming.desktop"
capture fake omarchy-remove-gaming-xbox-cloud
assert_status "xbox-cloud: no web app is no error, as in Omarchy" 0 "$STATUS"

setup omarchy-remove-xbox-controllers
mkpkg xpadneo-dkms
mkdir -p "$ROOT/etc/modprobe.d" "$ROOT/etc/modules-load.d"
touch "$ROOT/etc/modprobe.d/blacklist-xpad.conf" "$ROOT/etc/modules-load.d/xpadneo.conf"
capture oma omarchy-remove-gaming-xbox-controllers --dry-run
assert_dry_pure "xbox-controllers" "$OUTPUT"
assert_contains "xbox-controllers: haseen's files go with the catalogue entry" "$OUTPUT" \
    "DRYRUN: sudo rm -f /etc/modprobe.d/haseen-xpadneo.conf /etc/modules-load.d/haseen-xpadneo.conf"
assert_contains "xbox-controllers: the package goes" "$OUTPUT" "DRYRUN: sudo pacman -Rns --noconfirm xpadneo-dkms"
assert_contains "xbox-controllers: Omarchy's blacklist goes" "$OUTPUT" "DRYRUN: sudo rm -f -- /etc/modprobe.d/blacklist-xpad.conf"
assert_contains "xbox-controllers: Omarchy's module load goes" "$OUTPUT" "DRYRUN: sudo rm -f -- /etc/modules-load.d/xpadneo.conf"

# --- launcher entries ----------------------------------------------------------------
setup omarchy-remove-launcher
apps="$HOME/.local/share/applications"
mkdir -p "$apps" "$ROOT/usr/share/applications" "$HOME/.local/share/flatpak/exports/share/applications" \
    "$HOME/.local/share/flatpak/app/org.example.Flat"
printf '[Desktop Entry]\nExec=mytool\n' >"$apps/mytool.desktop"
printf '[Desktop Entry]\nExec=pkgapp\n' >"$ROOT/usr/share/applications/pkgapp.desktop"
mkpkg pkgapp
printf 'usr/share/applications/pkgapp.desktop\n' >>"$ROOT/var/lib/pacman/local/pkgapp-1.0-1/files"
printf '[Desktop Entry]\nExec=flatpak run org.example.Flat\n' >"$HOME/.local/share/flatpak/exports/share/applications/org.example.Flat.desktop"
printf '[Desktop Entry]\nExec=unowned\n' >"$ROOT/usr/share/applications/unowned.desktop"
capture oma omarchy-remove-launcher-entry mytool --dry-run
assert_status "launcher-entry dry run" 0 "$STATUS"
assert_dry_pure "launcher-entry" "$OUTPUT"
assert_contains "launcher-entry: the dry run plans the user launcher's deletion" "$OUTPUT" "DRYRUN: rm -f -- $apps/mytool.desktop"
[[ -e $apps/mytool.desktop ]] && _pass || _fail "launcher-entry: the dry run deleted the launcher"
capture oma omarchy-remove-launcher-entry pkgapp.desktop --dry-run
assert_dry_pure "launcher-entry (package)" "$OUTPUT"
assert_contains "launcher-entry: the dry run plans the package removal" "$OUTPUT" "DRYRUN: sudo pacman -Rns pkgapp"
capture fake omarchy-remove-launcher-entry mytool "My Tool"
[[ ! -e $apps/mytool.desktop ]] && _pass || _fail "launcher-entry: a user launcher is deleted"
capture fake omarchy-remove-launcher-entry pkgapp.desktop
assert_contains "launcher-entry: a package's entry uninstalls the package through haseen remove" "$(calls)" \
    "haseen-remove [package] [pkgapp]"
capture fake omarchy-remove-launcher-entry org.example.Flat
assert_contains "launcher-entry: a Flatpak's entry uninstalls the Flatpak" "$(calls)" "haseen-remove [flatpak] [org.example.Flat]"
capture fake omarchy-remove-launcher-entry unowned
assert_status "launcher-entry: an entry nobody owns is not guessed at" 1 "$STATUS"
assert_contains "launcher-entry: it says so" "$OUTPUT" "Don't know how to uninstall unowned.desktop"
[[ -e $ROOT/usr/share/applications/unowned.desktop && -e $ROOT/usr/share/applications/pkgapp.desktop ]] && _pass ||
    _fail "launcher-entry: nothing outside the user's applications is deleted"
capture fake omarchy-remove-launcher-entry missing
assert_status "launcher-entry: a missing entry fails" 1 "$STATUS"
capture fake omarchy-remove-launcher-entry
assert_status "launcher-entry: no id is a usage error" 1 "$STATUS"

# --- security --------------------------------------------------------------------
setup omarchy-remove-fido2
printf '#%%PAM-1.0\nauth      sufficient pam_u2f.so cue\nauth    sufficient pam_u2f.so cue authfile=/etc/fido2/fido2\nauth\t\tinclude\t\tsystem-auth\n' \
    >"$ROOT/etc/pam.d/sudo"
printf 'auth      sufficient pam_u2f.so cue\nauth      required pam_unix.so\n' >"$ROOT/etc/pam.d/polkit-1"
mkdir -p "$ROOT/etc/fido2"
mkpkg pam-u2f libfido2
mkpkg libfido2
mkpkg freerdp libfido2
capture oma omarchy-remove-security-fido2 --dry-run
assert_dry_pure "fido2" "$OUTPUT"
assert_contains "fido2: the foreign line is shown" "$OUTPUT" "authfile=/etc/fido2/fido2"
assert_contains "fido2: sudo is rewritten without either pam_u2f line" "$OUTPUT" \
    "DRYRUN: write /etc/pam.d/sudo (mode 0644):
    | #%PAM-1.0
    | auth		include		system-auth"
assert_contains "fido2: polkit loses haseen's line" "$OUTPUT" "DRYRUN: write /etc/pam.d/polkit-1 (mode 0644):
    | auth      required pam_unix.so"
assert_contains "fido2: Omarchy's authfile goes" "$OUTPUT" "DRYRUN: sudo rm -rf -- /etc/fido2"
assert_contains "fido2: pam-u2f goes" "$OUTPUT" "DRYRUN: sudo pacman -Rns --noconfirm pam-u2f"
assert_contains "fido2: libfido2 stays for freerdp" "$OUTPUT" "kept libfido2"
recording_sudo
capture oma omarchy-remove-security-fido2 <<<"n"
assert_contains "fido2: a no keeps the foreign line" "$(cat "$LOG.tee")" "authfile=/etc/fido2/fido2"
assert_not_contains "fido2: haseen's own line goes anyway" "$(cat "$LOG.tee")" "pam_u2f.so cue
"
assert_not_contains "fido2: the authfile stays with its line" "$(calls)" "rm -rf -- /etc/fido2"
assert_not_contains "fido2: the module stays while a line uses it" "$(calls)" "pacman"
: >"$LOG"
: >"$LOG.tee"
capture oma omarchy-remove-security-fido2 --yes </dev/null
assert_not_contains "fido2: --yes removes the foreign line" "$(cat "$LOG.tee")" "authfile=/etc/fido2/fido2"
assert_not_contains "fido2: --yes keeps Omarchy's authfile, the registered keys" "$(calls)" "rm -rf -- /etc/fido2"
assert_contains "fido2: and says how to delete it" "$OUTPUT" "answer at a terminal"
capture oma omarchy-remove-security-fido2 --purge --yes </dev/null
assert_status "fido2: --purge is not an option (only a terminal yes deletes keys)" 2 "$STATUS"
capture oma omarchy-remove-security-fido2 <<<$'y\ny\ny'
assert_contains "fido2: a yes at the terminal deletes the authfile" "$(calls)" "sudo rm -rf -- /etc/fido2"

setup omarchy-remove-fingerprint
printf '#%%PAM-1.0\nauth      [success=1 default=ignore] pam_exec.so quiet /usr/bin/omarchy-hw-laptop-closed\nauth      sufficient pam_fprintd.so\nauth\t\tinclude\t\tsystem-auth\n' \
    >"$ROOT/etc/pam.d/sudo"
touch "$ROOT/etc/pam.d/haseen-lock-fingerprint" "$ROOT/etc/pam.d/omarchy-lock-fingerprint"
recording_sudo
capture oma omarchy-remove-security-fingerprint <<<"n"
assert_status "fingerprint" 0 "$STATUS"
tee_out="$(cat "$LOG.tee")"
assert_not_contains "fingerprint: haseen's line goes" "$tee_out" "pam_fprintd"
assert_not_contains "fingerprint: a gate never outlives the rule it skips" "$tee_out" "omarchy-hw-laptop-closed"
assert_contains "fingerprint: the rest of the stack stays" "$tee_out" "system-auth"
assert_contains "fingerprint: haseen's lock service goes" "$(calls)" "sudo rm -f -- /etc/pam.d/haseen-lock-fingerprint"
assert_not_contains "fingerprint: a no keeps Omarchy's lock service" "$(calls)" "omarchy-lock-fingerprint"
capture oma omarchy-remove-security-fingerprint --yes
assert_not_contains "fingerprint: --yes alone keeps Omarchy's lock service" "$(calls)" "omarchy-lock-fingerprint"
capture oma omarchy-remove-security-fingerprint --purge --yes
assert_contains "fingerprint: --purge --yes deletes Omarchy's lock service" "$(calls)" \
    "sudo rm -f -- /etc/pam.d/omarchy-lock-fingerprint"
capture oma omarchy-remove-security-fingerprint --dry-run
assert_dry_pure "fingerprint" "$OUTPUT"

setup omarchy-remove-sshd
mkdir -p "$ROOT/usr/bin" "$ROOT/etc/ssh/sshd_config.d" "$HOME/.ssh"
printf '#!/bin/sh\n' >"$ROOT/usr/bin/ufw"
chmod +x "$ROOT/usr/bin/ufw"
touch "$ROOT/etc/ssh/sshd_config.d/90-haseen.conf"
echo "ssh-ed25519 AAAA test" >"$HOME/.ssh/authorized_keys"
capture oma omarchy-remove-security-sshd --dry-run
assert_dry_pure "sshd" "$OUTPUT"
assert_contains "sshd: the server is disabled" "$OUTPUT" "DRYRUN: sudo systemctl disable --now sshd.service"
assert_contains "sshd: haseen's drop-in goes" "$OUTPUT" "DRYRUN: sudo rm -f -- /etc/ssh/sshd_config.d/90-haseen.conf"
assert_contains "sshd: haseen's ufw rule goes" "$OUTPUT" "DRYRUN: sudo ufw --force delete allow 22/tcp"
assert_contains "sshd: the keys are asked about" "$OUTPUT" "DRYRUN: rm -f -- $HOME/.ssh/authorized_keys"
recording_sudo
capture oma omarchy-remove-security-sshd --yes
[[ -s $HOME/.ssh/authorized_keys ]] && _pass || _fail "sshd: --yes keeps the authorized keys"

setup omarchy-remove-docker
export USER=tester
printf 'docker:x:968:someone,tester\n' >"$ROOT/etc/group"
capture env OMARCHY_DEFER_REBOOT=1 HASEEN_SYSROOT="$ROOT" "$OMA/bin/omarchy-remove-security-sudoless-docker" --dry-run
assert_dry_pure "sudoless-docker" "$OUTPUT"
assert_contains "sudoless-docker: the user leaves the docker group" "$OUTPUT" "DRYRUN: sudo gpasswd -d tester docker"
assert_not_contains "sudoless-docker: a deferred reboot is not offered" "$OUTPUT" "Reboot now"
recording_sudo
capture oma omarchy-remove-security-sudoless-docker --yes
assert_contains "sudoless-docker: the reboot is recorded" "$(ls "$HOME/.local/state/haseen/omarchy-state" 2>/dev/null)" \
    "reboot-required"
assert_not_contains "sudoless-docker: --yes does not reboot" "$OUTPUT" "STUB-CALLED: systemd-run"
printf 'docker:x:968:someone\n' >"$ROOT/etc/group"
capture oma omarchy-remove-security-sudoless-docker --dry-run
assert_contains "sudoless-docker: nothing to do outside the group" "$OUTPUT" "Sudoless Docker is not enabled"

# --- services ----------------------------------------------------------------------
setup omarchy-remove-1password
mkdir -p "$ROOT/usr/share/chromium/extensions"
touch "$ROOT/usr/share/chromium/extensions/aeblfdkhhhdcdjpifhhbdiojplfjncoa.json"
mkpkg 1password
mkpkg 1password-cli
capture oma omarchy-remove-service-1password --dry-run
assert_dry_pure "1password" "$OUTPUT"
assert_contains "1password: Omarchy's extension file goes" "$OUTPUT" \
    "DRYRUN: sudo rm -f -- /usr/share/chromium/extensions/aeblfdkhhhdcdjpifhhbdiojplfjncoa.json"
assert_contains "1password: both packages go" "$OUTPUT" "DRYRUN: sudo pacman -Rns --noconfirm 1password 1password-cli"

setup omarchy-remove-dropbox
mkpkg dropbox
mkpkg libappindicator-gtk3
mkpkg panel-app libappindicator-gtk3
mkdir -p "$HOME/.config/haseen"
capture fake omarchy-remove-service-dropbox
assert_contains "dropbox: dropbox goes" "$(calls)" "haseen-remove [package] [dropbox] [--yes]"
assert_not_contains "dropbox: a helper another package needs stays" "$(calls)" "libappindicator"
assert_not_contains "dropbox: a plugin shell.json never named is left alone" "$(calls)" "haseen-plugin-disable"
printf '{"bar":{"right":["omarchy.dropbox"]}}\n' >"$HOME/.config/haseen/shell.json"
capture fake omarchy-remove-service-dropbox
assert_contains "dropbox: an enabled Omarchy plugin is turned off" "$(calls)" "haseen-plugin-disable [omarchy.dropbox]"

setup omarchy-remove-sunshine
mkdir -p "$ROOT/usr/bin" "$HOME/.config/hypr"
printf '#!/bin/sh\n' >"$ROOT/usr/bin/ufw"
chmod +x "$ROOT/usr/bin/ufw"
mkpkg sunshine
printf 'o.launch_on_start("sunshine")\n' >"$HOME/.config/hypr/autostart.lua"
before="$(cat "$HOME/.config/hypr/autostart.lua")"
capture oma omarchy-remove-service-sunshine --dry-run
assert_dry_pure "sunshine" "$OUTPUT"
assert_contains "sunshine: its user unit is disabled" "$OUTPUT" "DRYRUN: systemctl --user disable --now sunshine"
assert_contains "sunshine: the package goes" "$OUTPUT" "DRYRUN: sudo pacman -Rns --noconfirm sunshine"
assert_contains "sunshine: the LAN rules go" "$OUTPUT" "DRYRUN: sudo ufw --force delete allow in proto udp from 192.168.0.0/16 to any port 5353"
assert_contains "sunshine: the tailnet rules go" "$OUTPUT" "DRYRUN: sudo ufw --force delete allow in on tailscale0 to any port 47984 proto tcp"
assert_contains "sunshine: the autostart line is named, not edited" "$OUTPUT" "delete the line o.launch_on_start(\"sunshine\")"
assert_eq "sunshine: autostart.lua is untouched" "$before" "$(cat "$HOME/.config/hypr/autostart.lua")"

setup omarchy-remove-tailscale
mkpkg tailscale
mkdir -p "$HOME/.local/share/applications"
printf '[Desktop Entry]\nExec=helium --app=https://login.tailscale.com/admin\n' >"$HOME/.local/share/applications/Tailscale.desktop"
stub systemctl "echo \"systemctl \$*\" >>'$LOG'; exit 0"
capture fake omarchy-remove-service-tailscale
assert_contains "tailscale: removed with tailscaled through the catalogue entry" "$(calls)" "haseen-remove [app] [tailscale] [--yes]"
assert_contains "tailscale: Omarchy's receiver is disabled, not deleted" "$(calls)" \
    "systemctl --user disable --now omarchy-tailscale-receive.service"
assert_contains "tailscale: the web app goes" "$(calls)" "haseen-webapp-remove [Tailscale]"

# --- the owner's plugins are read-only (CLAUDE.md) ----------------------------------
# Every remover, as a dry run, under --yes and with a yes to every question,
# leaves ~/.config/omarchy (its plugins included) and DMS's plugins exactly as
# they were, even the plugins of the very services it removes and a data path
# that is a link into a plugin.
setup omarchy-remove-plugins
recording_sudo
stub systemctl "exit 0"
for c in mise tailscale rustup opam dropbox-cli composer openclaw update-desktop-database gtk-update-icon-cache; do
    stub "$c" "exit 0"
done
export USER=tester OMARCHY_DEFER_REBOOT=1
printf 'docker:x:968:tester\n' >"$ROOT/etc/group"
printf 'auth      sufficient pam_u2f.so cue\nauth      sufficient pam_fprintd.so\n' >"$ROOT/etc/pam.d/sudo"
for p in dropbox tailscale 1password sunshine steam hermes-desktop openclaw t3code-bin pam-u2f fprintd \
    heroic-games-launcher-bin lutris retroarch umu-launcher xpadneo-dkms google-chrome; do
    mkpkg "$p"
done
for dir in "$HOME/.config/omarchy/plugins" "$HOME/.config/DankMaterialShell/plugins"; do
    for id in omarchy.dropbox omarchy.tailscale omarchy.1password omarchy.sunshine hermes openclaw t3code steam; do
        mkdir -p "$dir/$id"
        printf '{"id":"%s"}\n' "$id" >"$dir/$id/plugin.json"
        printf 'import QtQuick\nItem {}\n' >"$dir/$id/Main.qml"
    done
done
ln -s "$HOME/.config/omarchy/plugins/t3code" "$HOME/.config/t3code"
ln -s "$HOME/.config/DankMaterialShell/plugins/hermes" "$HOME/.config/Hermes"
mkdir -p "$HOME/.config/haseen" "$HOME/.local/share/applications"
printf '{"bar":{"right":["omarchy.dropbox","omarchy.tailscale"]}}\n' >"$HOME/.config/haseen/shell.json"
printf '[Desktop Entry]\nExec=mytool\n' >"$HOME/.local/share/applications/mytool.desktop"
plugin_tree() {
    (cd "$HOME/.config" && find omarchy DankMaterialShell -printf '%p %y %m %s\n' | sort &&
        find omarchy DankMaterialShell -type f -exec sha256sum {} + | sort)
}
before="$(plugin_tree)"
for ((i = 0; i < 200; i++)); do echo y; done >"$SANDBOX/yes"
named=""
for name in "${GROUP[@]}"; do
    args=()
    case $name in
    *-browser) args=(chrome) ;;
    *-dev-env) args=(node) ;;
    *-launcher-entry) args=(mytool) ;;
    esac
    capture oma "$name" "${args[@]}" --dry-run
    [[ $OUTPUT != *omarchy/plugins* && $OUTPUT != *DankMaterialShell/plugins* ]] || named+="$name "
    capture fake "$name" "${args[@]}" --yes
    capture fake "$name" "${args[@]}" --purge --yes
    capture fake "$name" "${args[@]}" <"$SANDBOX/yes"
done
assert_eq "no remover's plan names the owner's plugin directories" "" "$named"
assert_eq "no remover changes ~/.config/omarchy or DMS's plugins" "$before" "$(plugin_tree)"
[[ ! -e $HOME/.config/t3code && ! -L $HOME/.config/t3code ]] && _pass ||
    _fail "a yes deletes the t3code link, not the plugin it points to"
