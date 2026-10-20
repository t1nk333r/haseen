# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen's answers to Omarchy's toggle, transcode, tui, update, version,
# voxtype, webapp and windows-vm commands (plan 093, group g6b).

B="$HASEEN_PATH/omarchy/bin"
G6B=(omarchy-toggle omarchy-toggle-bar omarchy-toggle-crash-capture omarchy-toggle-enabled
    omarchy-toggle-input-device omarchy-toggle-nightlight omarchy-transcode omarchy-transcode-ascii
    omarchy-tui-install omarchy-tui-remove omarchy-tui-remove-all omarchy-update-analyze-logs
    omarchy-update-aur-pkgs omarchy-update-confirm omarchy-update-lock omarchy-update-mise
    omarchy-update-orphan-pkgs omarchy-update-pkg-prune omarchy-update-requires-free-space
    omarchy-update-stay-awake omarchy-update-system-pkgs omarchy-version omarchy-version-pkgs
    omarchy-voxtype-config omarchy-voxtype-install omarchy-voxtype-model omarchy-voxtype-remove
    omarchy-voxtype-status omarchy-webapp-handler-hey omarchy-webapp-handler-zoom
    omarchy-webapp-install omarchy-webapp-remove omarchy-webapp-remove-all omarchy-windows-vm)

# --- every script: help, the notice, no direct sudo ---------------------------------
sandbox omarchy-g6b-help
bad=""
for name in "${G6B[@]}"; do
    capture "$B/$name" --help
    [[ $STATUS == 0 && -n $OUTPUT && $OUTPUT != *STUB-CALLED* ]] || bad+="$name($STATUS) "
done
assert_eq "every g6b script answers --help and runs nothing" "" "$bad"
bad=""
for name in "${G6B[@]}"; do
    grep -q 'Copyright (c) David Heinemeier Hansson' "$B/$name" || bad+="$name "
done
assert_eq "every g6b script names Omarchy's MIT notice" "" "$bad"
assert_eq "no g6b script calls sudo itself" "" \
    "$(cd "$B" && grep -ln 'sudo ' "${G6B[@]}" || true)"
assert_eq "no g6b script writes Omarchy's state" "" \
    "$(cd "$B" && grep -n 'local/state/omarchy\|\.config/omarchy' "${G6B[@]}" | grep -v ':[0-9]*:#' || true)"

# --- omarchy-toggle / omarchy-toggle-enabled ----------------------------------------
sandbox omarchy-g6b-toggle
STATE="$XDG_STATE_HOME/haseen"
capture "$B/omarchy-toggle" skip-vscode-theme-changes
assert_status "toggle on" 0 "$STATUS"
assert_eq "an Omarchy-only name lands in haseen's toggles dir" yes \
    "$([[ -e $STATE/toggles/omarchy/skip-vscode-theme-changes ]] && echo yes || echo no)"
capture "$B/omarchy-toggle-enabled" skip-vscode-theme-changes
assert_status "enabled reads it" 0 "$STATUS"
capture "$B/omarchy-toggle" skip-vscode-theme-changes
capture "$B/omarchy-toggle-enabled" skip-vscode-theme-changes
assert_status "toggled off again" 1 "$STATUS"
capture "$B/omarchy-toggle" screensaver-off on
assert_eq "screensaver-off is haseen's own flag" yes \
    "$([[ -e $STATE/flags/screensaver-off ]] && echo yes || echo no)"
capture "$B/omarchy-toggle-enabled" screensaver-off
assert_status "enabled reads haseen's flag" 0 "$STATUS"
capture "$B/omarchy-toggle" screensaver-off off
assert_eq "off removes it" no "$([[ -e $STATE/flags/screensaver-off ]] && echo yes || echo no)"
assert_eq "Omarchy's state dir is never created" no \
    "$([[ -e $XDG_STATE_HOME/omarchy || -e $HOME/.local/state/omarchy ]] && echo yes || echo no)"
capture "$B/omarchy-toggle"
assert_status "no name: Omarchy's usage exit" 1 "$STATUS"
capture "$B/omarchy-toggle" ../escape on
assert_status "a name leaving the store is refused" 1 "$STATUS"
capture "$B/omarchy-toggle" x bogus
assert_status "an unknown action: usage exit" 1 "$STATUS"
capture "$B/omarchy-toggle" suspend-off --dry-run
assert_contains "dry run plans the flag" "$OUTPUT" "DRYRUN: write $STATE/toggles/omarchy/suspend-off"
assert_dry_pure "omarchy-toggle" "$OUTPUT"
assert_eq "dry run leaves no flag" no "$([[ -e $STATE/toggles/omarchy/suspend-off ]] && echo yes || echo no)"

# --- omarchy-toggle-bar ---------------------------------------------------------------
# haseen's bar status over IPC: shown.
stub qs 'case "$*" in
*"ipc call bar status"*) echo "{\"hidden\":false}" ;;
*"ipc call nightlight status"*) echo "{\"enabled\":true,\"temperature\":4000,\"mode\":\"manual\"}" ;;
*) echo "STUB-CALLED: qs $*" >&2; exit 97 ;;
esac'
capture "$B/omarchy-toggle-bar" off --dry-run
assert_status "bar already shown: off does nothing" 0 "$STATUS"
assert_eq "and prints nothing" "" "$OUTPUT"
capture "$B/omarchy-toggle-bar" on --dry-run
assert_contains "on hides it through haseen toggle bar" "$OUTPUT" "DRYRUN: haseen-shell-ipc bar toggle"
assert_dry_pure "omarchy-toggle-bar" "$OUTPUT"
capture "$B/omarchy-toggle" bar-off on --dry-run
assert_contains "omarchy-toggle bar-off goes to the bar" "$OUTPUT" "DRYRUN: haseen-shell-ipc bar toggle"
capture "$B/omarchy-toggle-enabled" bar-off
assert_status "bar-off reads the bar's state" 1 "$STATUS"

# --- omarchy-toggle-nightlight --------------------------------------------------------
capture "$B/omarchy-toggle-nightlight" --status
assert_eq "--status from haseen's nightlight service" '{"enabled":true,"temperature":4000}' "$OUTPUT"
stub qs 'echo "STUB-CALLED: qs $*" >&2; exit 97'
mkdir -p "$STATE/flags" && : >"$STATE/flags/nightlight"
capture "$B/omarchy-toggle-nightlight" --status
assert_eq "--status without the shell reads the flag" '{"enabled":true,"temperature":null}' "$OUTPUT"
capture "$B/omarchy-toggle-nightlight" --dry-run
assert_contains "a toggle switches haseen's flag" "$OUTPUT" "DRYRUN: rm -f -- $STATE/flags/nightlight"
assert_dry_pure "omarchy-toggle-nightlight" "$OUTPUT"

# --- omarchy-toggle-crash-capture -----------------------------------------------------
sandbox omarchy-g6b-crash
DROPIN="$XDG_CONFIG_HOME/systemd/user/haseen-crash-watch.service.d/50-omarchy-crash-capture-off.conf"
capture "$B/omarchy-toggle-crash-capture" --dry-run
assert_contains "dry run plans the drop-in" "$OUTPUT" "DRYRUN: write $DROPIN"
assert_contains "which makes the watcher ignore every crash" "$OUTPUT" "Environment=HASEEN_CRASH_IGNORE=."
assert_contains "and restarts it" "$OUTPUT" "DRYRUN: systemctl --user restart haseen-crash-watch.service"
assert_dry_pure "omarchy-toggle-crash-capture" "$OUTPUT"
LOG="$SANDBOX/calls.log"
stub systemctl 'echo "systemctl $*" >>"'"$LOG"'"; case "$*" in *is-active*) exit 0 ;; esac'
stub notify-send 'exit 0'
capture "$B/omarchy-toggle-crash-capture"
assert_status "crash capture off" 0 "$STATUS"
assert_eq "the drop-in exists" yes "$([[ -f $DROPIN ]] && echo yes || echo no)"
assert_contains "the watcher restarts, never stops" "$(<"$LOG")" "systemctl --user restart haseen-crash-watch.service"
assert_not_contains "the watcher is never stopped" "$(<"$LOG")" "stop haseen-crash-watch"
capture "$B/omarchy-toggle-enabled" crash-capture-off
assert_status "the flag reads on" 0 "$STATUS"
capture "$B/omarchy-toggle-crash-capture"
assert_eq "toggled back: the drop-in is gone" no "$([[ -e $DROPIN ]] && echo yes || echo no)"

# --- omarchy-toggle-input-device ------------------------------------------------------
sandbox omarchy-g6b-input
stub hyprctl '[ "$1" = devices ] && { echo "{\"mice\":[{\"name\":\"elan-touchpad\"}]}"; exit 0; }; echo "STUB-CALLED: hyprctl $*" >&2; exit 97'
capture "$B/omarchy-toggle-input-device" touchpad off --dry-run
assert_contains "touchpad off through haseen hardware touchpad" "$OUTPUT" \
    "DRYRUN: hyprctl eval hl.device({ name = \"elan-touchpad\", enabled = false })"
assert_contains "persisted in haseen's hypr toggles" "$OUTPUT" "toggles/hypr/touchpad-disabled.lua"
assert_dry_pure "omarchy-toggle-input-device" "$OUTPUT"
capture "$B/omarchy-toggle-input-device" mouse
assert_status "an unknown kind: Omarchy's usage exit" 1 "$STATUS"

# --- omarchy-transcode / omarchy-transcode-ascii ------------------------------------
sandbox omarchy-g6b-transcode
PNG="$SANDBOX/shot.png"
printf '\x89PNG\r\n\x1a\n\x00\x00\x00\rIHDR\x00\x00\x00\x01\x00\x00\x00\x01\x08\x02\x00\x00\x00\x90wS\xde' >"$PNG"
capture "$B/omarchy-transcode" "$PNG" jpg low --dry-run
assert_contains "Omarchy's arguments reach haseen transcode" "$OUTPUT" "DRYRUN: magick $PNG -resize 1080x> -quality 85 -strip $SANDBOX/shot-low.jpg"
assert_dry_pure "omarchy-transcode" "$OUTPUT"
capture "$B/omarchy-transcode" --bogus
assert_status "an unknown option" 2 "$STATUS"
stub magick 'case "$*" in *info:*) echo "0 1" ;; *) printf "P1\n2 4\n1 1 1 1 1 1 1 1\n" ;; esac'
capture "$B/omarchy-transcode-ascii" "$PNG" "$SANDBOX/art.txt" --dry-run
assert_contains "the art is planned, not written" "$OUTPUT" "DRYRUN: write $SANDBOX/art.txt"
assert_contains "braille cells" "$OUTPUT" "⣿"
assert_dry_pure "omarchy-transcode-ascii" "$OUTPUT"
capture "$B/omarchy-transcode-ascii" "$PNG" "$SANDBOX/art.txt"
assert_eq "written for real" "⣿" "$(<"$SANDBOX/art.txt")"
capture "$B/omarchy-transcode-ascii" "$PNG" "$SANDBOX/art.txt" --mode bogus
assert_status "a bad mode: Omarchy's exit 1" 1 "$STATUS"

# --- omarchy-tui-install / -remove / -remove-all ------------------------------------
sandbox omarchy-g6b-tui
APPS="$XDG_DATA_HOME/applications"
stub xdg-terminal-exec 'exit 0'
capture "$B/omarchy-tui-install" "Disk Usage" "dua i" float dua --dry-run
assert_contains "dry run plans the launcher" "$OUTPUT" "DRYRUN: write $APPS/Disk Usage.desktop"
assert_dry_pure "omarchy-tui-install" "$OUTPUT"
capture "$B/omarchy-tui-install" "Disk Usage" "dua i" float dua
desk="$(<"$APPS/Disk Usage.desktop")"
assert_contains "float uses haseen's floating app-id" "$desk" "Exec=xdg-terminal-exec --app-id=haseen.floating -e dua i"
assert_contains "marked for removal" "$desk" "X-Haseen-TUI=float"
assert_contains "the icon name is kept" "$desk" "Icon=dua"
capture "$B/omarchy-tui-install" $'Evil\nExec=rm' "btop" tile btop
assert_contains "a newline in the name cannot start a key" "$(<"$APPS/Evil"$'\n'"Exec=rm.desktop")" 'Name=Evil\nExec=rm'
printf '[Desktop Entry]\nName=Btop\nExec=xdg-terminal-exec --app-id=TUI.float -e btop\n' >"$APPS/Btop.desktop"
printf '[Desktop Entry]\nName=Foot\nExec=foot\n' >"$APPS/foot.desktop"
capture env OMARCHY_REMOVE_NOTIFY=false "$B/omarchy-tui-remove" Btop --dry-run
assert_contains "dry run plans the removal" "$OUTPUT" "DRYRUN: rm -f -- $APPS/Btop.desktop"
assert_dry_pure "omarchy-tui-remove" "$OUTPUT"
capture env OMARCHY_REMOVE_NOTIFY=false "$B/omarchy-tui-remove" Btop
assert_eq "an Omarchy TUI launcher is removed" no "$([[ -e $APPS/Btop.desktop ]] && echo yes || echo no)"
capture env OMARCHY_REMOVE_NOTIFY=false "$B/omarchy-tui-remove" foot
assert_status "a launcher that is not a TUI is refused" 1 "$STATUS"
assert_eq "and kept" yes "$([[ -e $APPS/foot.desktop ]] && echo yes || echo no)"
printf '[Desktop Entry]\nName=Btop\nExec=xdg-terminal-exec --app-id=TUI.float -e btop\n' >"$APPS/Btop.desktop"
capture "$B/omarchy-tui-remove-all" --dry-run
assert_contains "remove-all finds Omarchy's" "$OUTPUT" "DRYRUN: rm -f -- $APPS/Btop.desktop"
assert_contains "and haseen's" "$OUTPUT" "DRYRUN: rm -f -- $APPS/Disk Usage.desktop"
assert_dry_pure "omarchy-tui-remove-all" "$OUTPUT"
capture "$B/omarchy-tui-remove-all" </dev/null
assert_status "remove-all without an answer removes nothing" 1 "$STATUS"
assert_eq "so the launcher stays" yes "$([[ -e $APPS/Btop.desktop ]] && echo yes || echo no)"
capture "$B/omarchy-tui-remove-all" --yes
assert_eq "--yes removes the TUIs" no "$([[ -e $APPS/Btop.desktop || -e "$APPS/Disk Usage.desktop" ]] && echo yes || echo no)"
assert_eq "and keeps other launchers" yes "$([[ -e $APPS/foot.desktop ]] && echo yes || echo no)"

# --- the update helpers -----------------------------------------------------------------
sandbox omarchy-g6b-update
ROOT="$SANDBOX/root"
mkdir -p "$ROOT/var/log" "$ROOT/usr/share/libalpm/hooks"
cat >"$ROOT/var/log/pacman.log" <<'EOF'
[2026-10-18T08:00:00+0000] [ALPM] transaction started
[2026-10-18T08:00:01+0000] [ALPM] running '90-mkinitcpio-install.hook'...
[2026-10-18T08:00:02+0000] [ALPM-SCRIPTLET] ==> Building image from preset: /etc/mkinitcpio.d/linux.preset: 'default'
[2026-10-18T08:00:05+0000] [ALPM] transaction completed
[2026-10-19T09:15:00+0000] [ALPM] transaction started
[2026-10-19T09:15:02+0000] [ALPM] upgraded linux (6.9.1-1 -> 6.9.2-1)
[2026-10-19T09:15:03+0000] [ALPM] running '90-mkinitcpio-install.hook'...
[2026-10-19T09:15:04+0000] [ALPM-SCRIPTLET] ==> Building image from preset: /etc/mkinitcpio.d/linux.preset: 'default'
[2026-10-19T09:15:09+0000] [ALPM-SCRIPTLET] ==> Initcpio image generation successful
[2026-10-19T09:15:10+0000] [ALPM] transaction completed
EOF
capture env HASEEN_SYSROOT="$ROOT" "$B/omarchy-update-analyze-logs"
assert_eq "the last build succeeded: nothing to report" "" "$OUTPUT"
printf '%s\n' "[2026-10-19T10:00:00+0000] [ALPM] transaction started" \
    "[2026-10-19T10:00:01+0000] [ALPM-SCRIPTLET] ==> Building image from preset: /etc/mkinitcpio.d/linux.preset: 'default'" \
    "[2026-10-19T10:00:02+0000] [ALPM-SCRIPTLET] ==> ERROR: module not found" >>"$ROOT/var/log/pacman.log"
capture env HASEEN_SYSROOT="$ROOT" "$B/omarchy-update-analyze-logs"
assert_contains "a build without success is reported" "$OUTPUT" "Initramfs generation may have failed"

capture env HASEEN_SYSROOT="$ROOT" TZ=UTC "$B/omarchy-version-pkgs"
assert_eq "the last upgrade, in Omarchy's format" \
    "$(TZ=UTC date -d 2026-10-19T09:15:02+0000 '+%A, %B %d %Y at %H:%M')" "$OUTPUT"
: >"$ROOT/var/log/pacman.log"
capture env HASEEN_SYSROOT="$ROOT" "$B/omarchy-version-pkgs"
assert_status "no upgrade recorded" 1 "$STATUS"
assert_contains "says so" "$OUTPUT" "no package upgrade recorded"

capture "$B/omarchy-version"
assert_eq "omarchy-version prints haseen's version" "$(<"$HASEEN_PATH/VERSION")" "$OUTPUT"
FAKE="$SANDBOX/fake/share/haseen"
mkdir -p "$FAKE" && ln -s "$HASEEN_PATH/lib" "$FAKE/lib"
capture env HASEEN_PATH="$FAKE" "$B/omarchy-version"
assert_status "no version known: exit 1" 1 "$STATUS"

capture env HASEEN_SYSROOT="$ROOT" "$B/omarchy-update-system-pkgs" --dry-run
assert_contains "system packages: haseen's pacman -Syu" "$OUTPUT" "DRYRUN: sudo pacman -Syu"
assert_not_contains "never Omarchy's overwrite policy" "$OUTPUT" "--overwrite"
assert_dry_pure "omarchy-update-system-pkgs" "$OUTPUT"
: >"$ROOT/usr/share/libalpm/hooks/00-omarchy-update-guard.hook"
capture env HASEEN_SYSROOT="$ROOT" OMARCHY_UPDATE_UNATTENDED=1 "$B/omarchy-update-system-pkgs" --dry-run
assert_contains "Omarchy's guard is told, as haseen update does" "$OUTPUT" \
    "DRYRUN: sudo env OMARCHY_ALLOW_DIRECT_PACMAN=1 pacman -Syu --noconfirm"

stub pacman 'case "$1" in -Qem) echo "foo 1-1" ;; -Qtdq) printf "orph1\norph2\n" ;; *) echo "STUB-CALLED: pacman $*" >&2; exit 97 ;; esac'
capture "$B/omarchy-update-aur-pkgs" --dry-run --yes
assert_contains "AUR packages through haseen's helper" "$OUTPUT" "DRYRUN: paru -Sua --noconfirm"
assert_dry_pure "omarchy-update-aur-pkgs" "$OUTPUT"
capture "$B/omarchy-update-orphan-pkgs" </dev/null
assert_contains "without a terminal orphans are only reported" "$OUTPUT" "2 orphaned package(s) found"
assert_dry_pure "orphan report" "$OUTPUT"
capture "$B/omarchy-update-orphan-pkgs" --dry-run
assert_contains "orphans are removed as root" "$OUTPUT" "DRYRUN: sudo pacman -Rns orph1 orph2"
assert_dry_pure "omarchy-update-orphan-pkgs" "$OUTPUT"
stub pacman 'exit 1'
capture "$B/omarchy-update-aur-pkgs" --dry-run
assert_eq "no foreign packages: nothing to do" "" "$OUTPUT"

capture "$B/omarchy-update-pkg-prune" --dry-run
assert_contains "the cache is pruned as root" "$OUTPUT" "DRYRUN: sudo paccache -rk2"
assert_dry_pure "omarchy-update-pkg-prune" "$OUTPUT"
stub mise 'echo "STUB-CALLED: mise $*" >&2; exit 97'
capture "$B/omarchy-update-mise" --dry-run
assert_contains "mise tools" "$OUTPUT" "DRYRUN: env MISE_MINIMUM_RELEASE_AGE=0 mise up"
assert_dry_pure "omarchy-update-mise" "$OUTPUT"

stub df 'printf "Avail\n1000\n"'
capture "$B/omarchy-update-requires-free-space"
assert_status "under 10 GiB free: exit 1" 1 "$STATUS"
assert_contains "and says why" "$OUTPUT" "at least 10 GiB free"
capture env HASEEN_UPDATE_FORCE=1 "$B/omarchy-update-requires-free-space"
assert_status "HASEEN_UPDATE_FORCE skips the check" 0 "$STATUS"
stub df 'printf "Avail\n99999999999999\n"'
capture "$B/omarchy-update-requires-free-space"
assert_status "enough space" 0 "$STATUS"

stub gum 'case "$1" in style) shift; printf "%s\n" "$@" ;; confirm) exit 1 ;; esac'
capture "$B/omarchy-update-confirm"
assert_status "declined: exit 1" 1 "$STATUS"
assert_contains "Update cancelled" "$OUTPUT" "Update cancelled"
assert_not_contains "no Omarchy release link" "$OUTPUT" "omarchy"
stub gum 'exit 0'
capture "$B/omarchy-update-confirm"
assert_status "accepted: exit 0" 0 "$STATUS"

capture "$B/omarchy-update-lock" run "$B/omarchy-update-lock" held
assert_status "run holds the lock for its command" 0 "$STATUS"
capture "$B/omarchy-update-lock" held
assert_status "outside it, held is false" 1 "$STATUS"
capture flock "$XDG_RUNTIME_DIR/haseen-update.lock" "$B/omarchy-update-lock" run true
assert_status "a second update is refused" 1 "$STATUS"
assert_contains "and says so" "$OUTPUT" "already running"
capture "$B/omarchy-update-lock" --dry-run run haseen update --yes
assert_eq "a dry run prints the command" "DRYRUN: (holding $XDG_RUNTIME_DIR/haseen-update.lock) haseen update --yes" "$OUTPUT"
capture "$B/omarchy-update-lock" run
assert_status "run without a command: usage exit 2" 2 "$STATUS"

# Stay Awake: the inhibitor is a stand-in that runs its command; idle is
# haseen's flag.
FLAG="$XDG_STATE_HOME/haseen/flags/idle-off"
stub systemd-inhibit 'while [ "${1#--}" != "$1" ]; do shift; done; exec "$@"'
capture "$B/omarchy-update-stay-awake" start --dry-run
assert_contains "start plans the inhibitor" "$OUTPUT" "DRYRUN: systemd-inhibit --what=sleep:idle --who=haseen-update"
assert_contains "and Stay Awake" "$OUTPUT" "haseen-toggle-idle off"
assert_dry_pure "omarchy-update-stay-awake" "$OUTPUT"
capture "$B/omarchy-update-stay-awake" start
assert_status "start" 0 "$STATUS"
assert_eq "idle is off while the update runs" yes "$([[ -e $FLAG ]] && echo yes || echo no)"
read -r ipid _ <"$XDG_RUNTIME_DIR/haseen-update-stay-awake/inhibit-pid"
assert_eq "the inhibitor runs" yes "$(kill -0 "$ipid" 2>/dev/null && echo yes || echo no)"
capture "$B/omarchy-update-stay-awake" stop
assert_status "stop" 0 "$STATUS"
assert_eq "idle is back on" no "$([[ -e $FLAG ]] && echo yes || echo no)"
assert_eq "the inhibitor is gone" no "$(kill -0 "$ipid" 2>/dev/null && echo yes || echo no)"
# The user's own Stay Awake survives the update, also when set again meanwhile.
mkdir -p "${FLAG%/*}" && : >"$FLAG"
capture "$B/omarchy-update-stay-awake" start
capture "$B/omarchy-update-stay-awake" stop
assert_eq "a Stay Awake the user set stays" yes "$([[ -e $FLAG ]] && echo yes || echo no)"
rm -f "$FLAG"
capture "$B/omarchy-update-stay-awake" start
rm -f "$FLAG" && : >"$FLAG"
capture "$B/omarchy-update-stay-awake" stop
assert_eq "one the user set again during the update stays too" yes "$([[ -e $FLAG ]] && echo yes || echo no)"
capture "$B/omarchy-update-stay-awake" bogus
assert_status "an unknown verb: usage exit 2" 2 "$STATUS"

# --- voxtype ---------------------------------------------------------------------------
sandbox omarchy-g6b-voxtype
ROOT="$SANDBOX/root"
mkdir -p "$ROOT/var/lib/pacman/local/voxtype-bin-0.5.0-1"
capture "$B/omarchy-voxtype-config"
assert_status "config without voxtype" 1 "$STATUS"
assert_contains "says how to get it" "$OUTPUT" "omarchy-voxtype-install"
capture "$B/omarchy-voxtype-remove"
assert_contains "remove without voxtype" "$OUTPUT" "Voxtype was not installed."
capture "$B/omarchy-voxtype-status"
assert_eq "status without voxtype: Omarchy's idle line" '{"alt": "", "class": "idle", "tooltip": ""}' "$OUTPUT"
mkdir -p "$SANDBOX/root-bare/var/lib/pacman/local"
capture env HASEEN_SYSROOT="$SANDBOX/root-bare" "$B/omarchy-voxtype-install" --dry-run
assert_contains "wtype from the repos" "$OUTPUT" "DRYRUN: sudo pacman -S --needed wtype"
assert_contains "voxtype-bin through haseen's source order (the AUR last)" "$OUTPUT" "DRYRUN: paru -S --needed voxtype-bin"
assert_contains "the config is seeded" "$OUTPUT" "DRYRUN: write $XDG_CONFIG_HOME/voxtype/config.toml"
assert_contains "with Voxtype's own hotkey off" "$OUTPUT" "enabled = false"
assert_contains "the model is set up" "$OUTPUT" "DRYRUN: voxtype setup --download --no-post-install"
assert_dry_pure "omarchy-voxtype-install" "$OUTPUT"
stub voxtype 'echo "{\"class\":\"recording\"}"'
stub foot 'exit 0'
capture env TERMINAL=foot "$B/omarchy-voxtype-config" --dry-run
assert_contains "configure in haseen's floating terminal" "$OUTPUT" "--app-id=haseen.floating"
assert_contains "runs voxtype configure" "$OUTPUT" "voxtype configure"
assert_dry_pure "omarchy-voxtype-config" "$OUTPUT"
capture env TERMINAL=foot "$B/omarchy-voxtype-model" --dry-run
assert_contains "model setup in the floating terminal" "$OUTPUT" "voxtype setup model"
capture "$B/omarchy-voxtype-status"
assert_eq "status follows voxtype" '{"class":"recording"}' "$OUTPUT"
capture env HASEEN_SYSROOT="$ROOT" "$B/omarchy-voxtype-remove" --dry-run
assert_contains "the service goes" "$OUTPUT" "DRYRUN: systemctl --user disable --now voxtype.service"
assert_contains "the package through haseen remove" "$OUTPUT" "DRYRUN: sudo pacman -Rns voxtype-bin"
assert_contains "config and models after confirmation" "$OUTPUT" "DRYRUN: rm -rf -- $XDG_CONFIG_HOME/voxtype"
assert_dry_pure "omarchy-voxtype-remove" "$OUTPUT"

# --- web apps --------------------------------------------------------------------------
sandbox omarchy-g6b-webapp
# The handlers launch the sibling omarchy-launch-webapp: a copy of each handler
# beside a recording launcher.
FOMA="$SANDBOX/omarchy"
mkdir -p "$FOMA/bin"
ln -s "$HASEEN_PATH/omarchy/lib.sh" "$FOMA/lib.sh"
cp "$B/omarchy-webapp-handler-hey" "$B/omarchy-webapp-handler-zoom" "$FOMA/bin/"
printf '#!/bin/sh\necho "LAUNCH $*"\n' >"$FOMA/bin/omarchy-launch-webapp"
chmod +x "$FOMA/bin/omarchy-launch-webapp"
capture "$FOMA/bin/omarchy-webapp-handler-hey" "mailto:jane@example.com?subject=Hi there"
assert_eq "HEY compose for the address only" "LAUNCH https://app.hey.com/messages/new?to=jane@example.com" "$OUTPUT"
capture "$FOMA/bin/omarchy-webapp-handler-hey"
assert_eq "HEY without a link" "LAUNCH https://app.hey.com" "$OUTPUT"
capture "$FOMA/bin/omarchy-webapp-handler-zoom" "zoommtg://zoom.us/join?action=join&confno=123&pwd=abc"
assert_eq "Zoom joins the meeting" "LAUNCH https://app.zoom.us/wc/join/123?pwd=abc" "$OUTPUT"

APPS="$XDG_DATA_HOME/applications"
stub xdg-settings 'echo chromium.desktop'
capture "$B/omarchy-webapp-install" HEY https://app.hey.com HEY --dry-run
assert_contains "three arguments: haseen webapp install" "$OUTPUT" "DRYRUN: write $APPS/HEY.desktop"
assert_contains "in app mode" "$OUTPUT" '--app=https://app.hey.com'
assert_dry_pure "omarchy-webapp-install" "$OUTPUT"
capture "$B/omarchy-webapp-install" HEY https://app.hey.com HEY "" "x-scheme-handler/mailto" --dry-run
assert_contains "a MimeType is added" "$OUTPUT" "MimeType=x-scheme-handler/mailto"
printf 'PNG' >"$SANDBOX/claw.png"
capture "$B/omarchy-webapp-install" OpenClaw http://127.0.0.1:18789 "$SANDBOX/claw.png" omarchy-launch-openclaw
assert_status "a custom Exec" 0 "$STATUS"
desk="$(<"$APPS/OpenClaw.desktop")"
assert_contains "runs that command" "$desk" "Exec=omarchy-launch-openclaw"
assert_contains "and is marked for removal" "$desk" "X-Haseen-WebApp=http://127.0.0.1:18789"
assert_eq "its icon is copied" yes "$([[ -f $XDG_DATA_HOME/icons/hicolor/256x256/apps/openclaw.png ]] && echo yes || echo no)"
capture "$B/omarchy-webapp-install" "a/b" https://x.test x cmd
assert_status "a name with a slash is refused" 1 "$STATUS"

printf '[Desktop Entry]\nName=Basecamp\nExec=omarchy-launch-webapp https://launchpad.37signals.com\n' >"$APPS/Basecamp.desktop"
printf '[Desktop Entry]\nName=Mail\nExec=chromium "--app=https://mail.example"\n' >"$APPS/Mail.desktop"
printf '[Desktop Entry]\nName=Foot\nExec=foot\n' >"$APPS/foot.desktop"
mkdir -p "$XDG_DATA_HOME/icons/hicolor/256x256/apps" && : >"$XDG_DATA_HOME/icons/hicolor/256x256/apps/basecamp.png"
capture env OMARCHY_REMOVE_NOTIFY=false "$B/omarchy-webapp-remove" Basecamp --dry-run
assert_contains "Omarchy's web apps are found" "$OUTPUT" "DRYRUN: rm -f -- $APPS/Basecamp.desktop"
assert_dry_pure "omarchy-webapp-remove" "$OUTPUT"
capture env OMARCHY_REMOVE_NOTIFY=false "$B/omarchy-webapp-remove" Basecamp
assert_eq "and removed with their icon" no \
    "$([[ -e $APPS/Basecamp.desktop || -e $XDG_DATA_HOME/icons/hicolor/256x256/apps/basecamp.png ]] && echo yes || echo no)"
capture env OMARCHY_REMOVE_NOTIFY=false "$B/omarchy-webapp-remove" Nothing
assert_status "an unknown name succeeds, as Omarchy's callers expect" 0 "$STATUS"
assert_contains "but says so" "$OUTPUT" "no web app named 'Nothing'"
capture env OMARCHY_REMOVE_NOTIFY=false "$B/omarchy-webapp-remove" foot
assert_eq "a launcher that is not a web app stays" yes "$([[ -e $APPS/foot.desktop ]] && echo yes || echo no)"
capture "$B/omarchy-webapp-remove-all" --dry-run
assert_contains "remove-all finds haseen's" "$OUTPUT" "$APPS/Mail.desktop"
assert_contains "and custom-Exec ones" "$OUTPUT" "$APPS/OpenClaw.desktop"
assert_not_contains "never other launchers" "$OUTPUT" "foot.desktop"
assert_dry_pure "omarchy-webapp-remove-all" "$OUTPUT"
capture "$B/omarchy-webapp-remove-all" --yes
assert_eq "--yes removes them" no "$([[ -e $APPS/Mail.desktop || -e $APPS/OpenClaw.desktop ]] && echo yes || echo no)"
assert_eq "and keeps the rest" yes "$([[ -e $APPS/foot.desktop ]] && echo yes || echo no)"

# --- omarchy-windows-vm ----------------------------------------------------------------
sandbox omarchy-g6b-winvm
ROOT="$SANDBOX/root"
mkdir -p "$ROOT/var/lib/pacman/local" "$SANDBOX/vm"
export HASEEN_WINDOWS_DIR="$SANDBOX/vm" HASEEN_DOCKER_SOCKET="$SANDBOX/no-docker.sock"
capture env HASEEN_SYSROOT="$ROOT" "$B/omarchy-windows-vm" install --dry-run
assert_status "install dry-run" 0 "$STATUS"
assert_contains "docker from haseen's catalogue" "$OUTPUT" "DRYRUN: sudo pacman -S --needed docker docker-compose"
assert_contains "FreeRDP and gum through haseen install" "$OUTPUT" "freerdp gum"
assert_not_contains "never the docker group" "$OUTPUT" "usermod"
assert_contains "the launcher runs this command" "$OUTPUT" "Exec=omarchy-windows-vm launch"
assert_contains "the compose is written as root" "$OUTPUT" "__priv write_compose"
assert_not_contains "the password is never printed" "$OUTPUT" "PASSWORD=admin"
assert_dry_pure "omarchy-windows-vm install" "$OUTPUT"
cat >"$SANDBOX/vm/docker-compose.yml" <<'EOF'
services:
  windows:
    environment:
      USERNAME: "jane"
      PASSWORD: "s3cret"
EOF
capture "$B/omarchy-windows-vm" launch --dry-run
assert_contains "launch connects with the stored user" "$OUTPUT" "DRYRUN: xfreerdp3 /u:jane /p:<password>"
assert_not_contains "never showing the password" "$OUTPUT" "s3cret"
assert_dry_pure "omarchy-windows-vm launch" "$OUTPUT"
capture "$B/omarchy-windows-vm" stop
assert_status "a checkout is never elevated" 1 "$STATUS"
assert_contains "and says why" "$OUTPUT" "refusing to run a non-root-owned command as root"
assert_dry_pure "omarchy-windows-vm stop" "$OUTPUT"
capture "$B/omarchy-windows-vm" __priv status
assert_status "the privileged entry needs root" 1 "$STATUS"
capture "$B/omarchy-windows-vm" bogus
assert_status "an unknown command" 1 "$STATUS"
unset HASEEN_WINDOWS_DIR HASEEN_DOCKER_SOCKET
