# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Menu (plan 016): default/menu.jsonc parses and holds exactly the owner's
# selection (no Learn, no web apps), every action's `haseen …` command exists
# in bin/, the model's overlay merge/guards/catalog rows behave, and the
# Menu-owned commands do what they say and stay pure under --dry-run.

MENU_JSONC="$HASEEN_PATH/default/menu.jsonc"
MODEL_JS="$HASEEN_PATH/shell/plugins/haseen.menu/MenuModel.js"
# node runs the QML model's pure JS; looked up before sandbox() narrows PATH.
NODE="$(command -v node || true)"

# menu_json — menu.jsonc as plain JSON (the model's own stripping rules).
menu_json() {
    grep -v '^[[:space:]]*//' "$MENU_JSONC" | perl -0pe 's/,(\s*[}\]])/$1/g'
}

# model JS — run JS with the model's functions in scope (`.pragma` dropped).
model() {
    "$NODE" -e "$(grep -v '^\.pragma' "$MODEL_JS")
$1" "${@:2}"
}

# resolve WORDS... — the bin/ command `haseen WORDS` routes to (longest
# prefix, as bin/haseen does), or nothing.
resolve() {
    local n name
    for ((n = $#; n > 0; n--)); do
        name="haseen-$(
            IFS=-
            echo "${*:1:n}"
        )"
        [[ -x $REPO/bin/$name ]] && {
            echo "$name"
            return 0
        }
    done
    return 1
}

# --- menu.jsonc ----------------------------------------------------------------
sandbox menu-jsonc
capture bash -c "$(declare -f menu_json); MENU_JSONC='$MENU_JSONC' menu_json | jq -e 'type == \"object\" and length > 100'"
assert_status "menu.jsonc parses as JSONC" 0 "$STATUS"
JSON="$(menu_json)"
ids="$(jq -r 'keys[]' <<<"$JSON")"
for id in apps trigger style setup install remove update about system \
    trigger.capture.screenshot trigger.capture.screenrecord.webcam trigger.capture.screenrecord-stop \
    trigger.capture.text trigger.capture.qr trigger.capture.color trigger.emoji trigger.reminder.set \
    trigger.toggle.idle trigger.toggle.dnd trigger.toggle.one-window-ratio trigger.hardware.hybrid-gpu \
    trigger.share.receive trigger.tests.disk trigger.transcode style.theme style.background style.font \
    style.bar.position.left style.bar.transparency style.screensaver.image style.about.text \
    setup.monitors setup.network.dns.custom setup.network.qr setup.default.agent setup.plugin.remove \
    setup.config.hyprland setup.config.nightlight setup.dotfiles.clone setup.security.passwordless-sudo setup.secureboot.setup \
    setup.ai.chat update.firmware update.timezone update.password.drive update.hardware.trackpad \
    update.config.nightlight system.screensaver system.hibernate system.shutdown; do
    assert_contains "menu has $id" "$ids"$'\n' "$id"$'\n'
done
assert_not_contains "no Learn group" $'\n'"$ids" $'\n'"learn"
assert_not_contains "no web apps (ids)" "$ids" "webapp"
assert_not_contains "no web apps (actions)" "$(jq -r '.[].action // empty' <<<"$JSON")" "webapp"
assert_not_contains "no URLs in actions" "$(jq -r '.[].action // empty' <<<"$JSON")" "://"
for gone in crash-capture herdr xcompose direct-boot reset channel; do
    assert_not_contains "omitted: $gone" "$ids" "$gone"
done
assert_eq "about runs haseen about" "haseen about" "$(jq -r '.about.action' <<<"$JSON")"
assert_eq "apps uses the launcher provider" "apps" "$(jq -r '.apps.provider' <<<"$JSON")"
assert_eq "install rendered from the catalog" "catalog-install" "$(jq -r '.install.provider' <<<"$JSON")"
assert_eq "remove rendered from the catalog" "catalog-remove" "$(jq -r '.remove.provider' <<<"$JSON")"
# Style opens the pickers, as Omarchy's Style menu does; a bare list of
# background files left the background picker panel unreachable.
assert_eq "style.theme opens the theme picker" "haseen shell ipc panel toggle haseen.themepicker" "$(jq -r '."style.theme".action' <<<"$JSON")"
assert_eq "style.background opens the background picker" "haseen shell ipc panel toggle haseen.background" "$(jq -r '."style.background".action' <<<"$JSON")"
assert_eq "next background stays in the menu" "haseen theme bg next" "$(jq -r '."style.next-background".action' <<<"$JSON")"
for id in $(jq -r '.[].action // empty' <<<"$JSON" | sed -n 's/^haseen shell ipc panel toggle \([a-z0-9.-]*\)$/\1/p' | sort -u); do
    assert_eq "menu panel $id is a shipped panel plugin" "panel" \
        "$(jq -r '.kinds[] | select(. == "panel")' "$REPO/share/haseen/shell/plugins/$id/manifest.json" 2>/dev/null)"
done

# Every `haseen …` command an action or guard names must exist. Commands of
# other plan-016 slices are listed until they land.
missing=()
while IFS= read -r line; do
    # Each `haseen word word…` occurrence, words up to the first non-word.
    while [[ $line =~ (^|[^a-z.-])haseen((\ [a-z0-9][a-z0-9-]*)+) ]]; do
        read -r -a words <<<"${BASH_REMATCH[2]}"
        resolve "${words[@]}" >/dev/null || missing+=("haseen ${words[*]:0:2}")
        line="${line#*"${BASH_REMATCH[0]}"}"
    done
done < <(jq -r '.[] | (.action // empty), (.when // empty), (.checked // empty), (.disabled // empty)' <<<"$JSON")
if ((${#missing[@]} == 0)); then
    _pass
else
    _fail "menu commands exist in bin/" "missing: $(printf '%s\n' "${missing[@]}" | sort -u | paste -sd, -)"
fi

# --- model (MenuModel.js) ------------------------------------------------------
if [[ -z $NODE ]]; then
    echo "  SKIP model checks: node not found" >&2
else
    out="$(model "
const d = parseMenuJsonc(require('fs').readFileSync('$MENU_JSONC', 'utf8'));
const u = parseMenuJsonc('{\n // comment\n \"system.lock\": {\"label\": \"Lock now\"},\n \"system.hibernate\": {\"hidden\": true},\n \"mine\": {\"label\": \"Mine\"},\n \"mine.hello\": {\"label\": \"Hello\", \"action\": \"echo hi\",},\n}');
const m = mergeMenuSources(d, u);
const it = m.items;
console.log([it['system.lock'].label, it['system.lock'].action, String(!!it['system.hibernate']),
  it.mine.parent, it['mine.hello'].kind, String(m.itemOrder.indexOf('mine') > m.itemOrder.indexOf('system.shutdown')),
  resolveRoute(it, m.itemOrder, 'power'), resolveRoute(it, m.itemOrder, 'capture'), resolveRoute(it, m.itemOrder, ''),
  String(parseMenuJsonc('{broken') === null)].join('|'));
")"
    assert_eq "overlay merge, hide, add, routes" "Lock now|haseen system lock|false|root|action|true|system|trigger.capture|root|true" "$out"

    # Guards: one bash batch, `when` hides until it answers true.
    script="$(model "
const m = mergeMenuSources(parseMenuJsonc('{\"a\":{\"label\":\"A\",\"when\":\"true\",\"action\":\"x\"},\"b\":{\"label\":\"B\",\"when\":\"false\",\"action\":\"x\"},\"c\":{\"label\":\"C\",\"checked\":\"haseen-flag dnd\",\"action\":\"x\"}}'), []);
process.stdout.write(guardScript(m.items));")"
    mkdir -p "$XDG_STATE_HOME/haseen/flags"
    : >"$XDG_STATE_HOME/haseen/flags/dnd"
    guard_out="$(bash -c "$script")"
    out="$(model "
const m = mergeMenuSources(parseMenuJsonc('{\"a\":{\"label\":\"A\",\"when\":\"true\",\"action\":\"x\"},\"b\":{\"label\":\"B\",\"when\":\"false\",\"action\":\"x\"},\"c\":{\"label\":\"C\",\"checked\":\"haseen-flag dnd\",\"action\":\"x\"}}'), []);
const r = parseGuardOutput(process.argv[1]);
const vis = id => isVisible(m.items, m.itemOrder, r.w, m.items[id], 0);
const before = isVisible(m.items, m.itemOrder, {}, m.items.a, 0);
console.log([vis('a'), vis('b'), vis('c'), before, labelFor(m.items.c, r.c, r.d)].join('|'));
" "$guard_out")"
    assert_eq "guards: when/checked from one batch" "true|false|true|false|C ✓" "$out"

    # Catalog rows (Catalog's catalog.json shape).
    out="$(model "
const cat = {categories: [{id: 'browser', label: 'Browser'}, {id: 'gaming', label: 'Gaming'}],
  entries: [{id: 'firefox', label: 'Firefox', category: 'browser'}, {id: 'zen', label: 'Zen', category: 'browser'},
            {id: 'steam', label: 'Steam', category: 'gaming', when: '[[ -e /x ]]'}]};
const ins = catalogRows('install', cat, ['firefox'], 'install');
const rem = catalogRows('remove', cat, ['firefox'], 'remove');
console.log([ins.map(r => r.id + (r.disabledNow ? '!' : '')).join(','), ins[1].action, ins[4].when,
  rem.map(r => r.id).join(','), rem[1].action].join('|'));
")"
    assert_eq "catalog install/remove rows" "install.browser,install.browser.firefox!,install.browser.zen,install.gaming,install.gaming.steam|haseen install app 'firefox'|[[ -e /x ]]|remove.browser,remove.browser.firefox|haseen remove app 'firefox'" "$out"
    assert_eq "panel actions run in-process" "haseen.emoji" "$(model "console.log(panelAction('haseen shell ipc panel toggle haseen.emoji'))")"
fi

# --- haseen menu / about ---------------------------------------------------------
sandbox menu-cli
for c in menu about system "setup dns" "setup default" "setup fingerprint" "setup fido2" "setup sshd" \
    "setup ssh-agent" "setup passwordless-sudo" "font list" "font set" "font current" branding \
    "config edit" "config terminal" "config plugin"; do
    # shellcheck disable=SC2086
    capture haseen $c --help
    assert_status "$c --help" 0 "$STATUS"
    assert_contains "$c --help usage" "$OUTPUT" "Usage: haseen $c"
done
capture haseen menu trigger.capture --dry-run
assert_eq "menu path over IPC" "DRYRUN: haseen shell ipc menu toggle trigger.capture" "$OUTPUT"
assert_dry_pure "menu" "$OUTPUT"
capture haseen menu 'a;b' --dry-run
assert_status "menu rejects odd paths" 1 "$STATUS"
capture haseen about --dry-run
assert_eq "about opens the view" "DRYRUN: haseen shell ipc menu toggle :about" "$OUTPUT"

ROOT="$SANDBOX/root"
mkdir -p "$ROOT/etc" "$ROOT/proc/sys/kernel" "$ROOT/sys/power" "$ROOT/etc/pam.d"
printf 'NAME="CachyOS Linux"\nPRETTY_NAME="CachyOS"\nVERSION_ID=rolling\n' >"$ROOT/etc/os-release"
echo 6.17.1-2-cachyos >"$ROOT/proc/sys/kernel/osrelease"
printf 'processor\t: 0\nmodel name\t: 11th Gen Intel(R) Core(TM) i7-1165G7 @ 2.80GHz\nprocessor\t: 1\nmodel name\t: x\n' >"$ROOT/proc/cpuinfo"
printf 'MemTotal:       16000000 kB\nMemAvailable:    8000000 kB\n' >"$ROOT/proc/meminfo"
echo "93784.12 1000.00" >"$ROOT/proc/uptime"
capture env HASEEN_SYSROOT="$ROOT" haseen about --facts
assert_status "about --facts" 0 "$STATUS"
assert_contains "facts: OS" "$OUTPUT" $'OS\tCachyOS rolling'
assert_contains "facts: kernel" "$OUTPUT" $'Kernel\t6.17.1-2-cachyos'
assert_contains "facts: CPU" "$OUTPUT" $'CPU\t11th Gen Intel Core i7-1165G7 (2)'
assert_contains "facts: memory" "$OUTPUT" $'Memory\t7.6 / 15.3 GiB'
assert_contains "facts: uptime" "$OUTPUT" $'Uptime\t1d 2h 3m'
assert_contains "facts: version" "$OUTPUT" $'haseen\t'"$(cat "$HASEEN_PATH/VERSION")"
# Omarchy writes its name over /etc/os-release; the OS line names the
# distribution underneath (/usr/lib/os-release), or Linux without one.
OROOT="$SANDBOX/omarchy-root"
mkdir -p "$OROOT/etc" "$OROOT/usr/lib"
printf 'NAME="Omarchy"\nPRETTY_NAME="Omarchy"\nID=omarchy\nID_LIKE=arch\nVERSION_ID="4.0.4"\n' >"$OROOT/etc/os-release"
capture env HASEEN_SYSROOT="$OROOT" haseen about --facts
assert_contains "facts: no base os-release under Omarchy is Linux" "$OUTPUT" $'OS\tLinux'
printf 'NAME="Arch Linux"\nPRETTY_NAME="Arch Linux"\nID=arch\nBUILD_ID=rolling\n' >"$OROOT/usr/lib/os-release"
capture env HASEEN_SYSROOT="$OROOT" haseen about --facts
assert_contains "facts: OS under Omarchy is the base distribution" "$OUTPUT" $'OS\tArch Linux\n'
assert_not_contains "facts: never Omarchy" "$OUTPUT" "Omarchy"

# --- haseen system ---------------------------------------------------------------
# The System menu is Omarchy's, row for row, each on a haseen command.
assert_eq "system menu: Omarchy's rows, in order" \
    "system.screensaver=haseen screensaver --force
system.lock=haseen system lock
system.suspend=haseen system suspend
system.hibernate=haseen system hibernate
system.logout=haseen system logout
system.reboot=haseen system reboot
system.shutdown=haseen system shutdown" \
    "$(jq -r 'to_entries[] | select(.key | startswith("system.")) | "\(.key)=\(.value.action)"' <<<"$JSON")"
assert_eq "system menu: hibernate shows only once it is set up" "haseen system hibernate --available" \
    "$(jq -r '."system.hibernate".when' <<<"$JSON")"

# Hibernate is offered only when it would resume: zram swap as large as RAM
# is not enough (the image would live in the memory being saved).
echo "freeze mem disk" >"$ROOT/sys/power/state"
echo 6400000000 >"$ROOT/sys/power/image_size"
printf 'HOOKS=(base udev autodetect block encrypt filesystems fsck)\n' >"$ROOT/etc/mkinitcpio.conf"
printf 'root=/dev/mapper/root rw\n' >"$ROOT/proc/cmdline"
printf 'Filename Type Size Used Priority\n/dev/zram0 partition 17000000 0 100\n' >"$ROOT/proc/swaps"
capture env HASEEN_SYSROOT="$ROOT" haseen system hibernate --available
assert_status "hibernate unavailable: zram only" 1 "$STATUS"
printf 'Filename Type Size Used Priority\n/swap/swapfile file 17000000 0 -2\n' >"$ROOT/proc/swaps"
capture env HASEEN_SYSROOT="$ROOT" haseen system hibernate --available
assert_status "hibernate unavailable: swapfile but no resume" 1 "$STATUS"
capture env HASEEN_SYSROOT="$ROOT" haseen system hibernate --dry-run
assert_status "hibernate refuses when not set up" 1 "$STATUS"
assert_contains "hibernate says what to check" "$OUTPUT" "haseen hibernation status"
printf 'HOOKS=(base systemd autodetect block sd-encrypt filesystems fsck)\n' >"$ROOT/etc/mkinitcpio.conf"
printf 'root=/dev/mapper/root rw resume=/dev/mapper/root resume_offset=1\n' >"$ROOT/proc/cmdline"
capture env HASEEN_SYSROOT="$ROOT" haseen system hibernate --available
assert_status "hibernate available: swapfile + resume" 0 "$STATUS"
capture env HASEEN_SYSROOT="$ROOT" haseen hibernation status --quiet
assert_status "the menu agrees with haseen hibernation status" 0 "$STATUS"

# Every System row runs (dry) as written, hibernate included now it is set up.
while IFS= read -r action; do
    # shellcheck disable=SC2086 # the action is a word list, as the menu runs it
    capture env HASEEN_SYSROOT="$ROOT" $action --dry-run
    assert_status "system menu: $action" 0 "$STATUS"
    assert_dry_pure "system menu: $action" "$OUTPUT"
done < <(jq -r 'to_entries[] | select(.key | startswith("system.")) | .value.action' <<<"$JSON")
capture env HASEEN_SYSROOT="$ROOT" haseen system hibernate --dry-run
assert_eq "hibernate is systemctl hibernate" "DRYRUN: systemctl hibernate" "$OUTPUT"
capture haseen system shutdown --dry-run
assert_eq "shutdown is poweroff" "DRYRUN: systemctl poweroff" "$OUTPUT"
capture haseen system nap
assert_status "system rejects unknown" 2 "$STATUS"

# --- haseen setup dns / default ----------------------------------------------------
capture env HASEEN_SYSROOT="$ROOT" haseen setup dns
assert_eq "dns current: dhcp without drop-in" "dhcp" "$OUTPUT"
capture env HASEEN_SYSROOT="$ROOT" haseen setup dns cloudflare --dry-run
assert_dry_pure "dns cloudflare" "$OUTPUT"
assert_contains "dns drop-in path" "$OUTPUT" "write /etc/systemd/resolved.conf.d/90-haseen-dns.conf"
assert_contains "dns cloudflare DoT" "$OUTPUT" "DNS=1.1.1.1#cloudflare-dns.com"
assert_contains "dns marker" "$OUTPUT" "# haseen-dns: cloudflare"
assert_contains "dns restart" "$OUTPUT" "DRYRUN: sudo systemctl restart systemd-resolved"
mkdir -p "$ROOT/etc/systemd/resolved.conf.d"
printf '# haseen-dns: google\n' >"$ROOT/etc/systemd/resolved.conf.d/90-haseen-dns.conf"
capture env HASEEN_SYSROOT="$ROOT" haseen setup dns
assert_eq "dns current from drop-in" "google" "$OUTPUT"
capture env HASEEN_SYSROOT="$ROOT" haseen setup dns dhcp --dry-run
assert_contains "dns dhcp removes drop-in" "$OUTPUT" "DRYRUN: sudo rm -f /etc/systemd/resolved.conf.d/90-haseen-dns.conf"
capture env HASEEN_SYSROOT="$ROOT" haseen setup dns custom 9.9.9.9 'x;y' --dry-run
assert_status "dns rejects bad server" 1 "$STATUS"
capture env HASEEN_SYSROOT="$ROOT" haseen setup dns custom 9.9.9.9 149.112.112.112 --dry-run
assert_contains "dns custom servers" "$OUTPUT" "DNS=9.9.9.9 149.112.112.112"

env_file="$XDG_CONFIG_HOME/uwsm/env.d/60-haseen-defaults"
capture haseen setup default terminal kitty --dry-run
assert_dry_pure "default terminal" "$OUTPUT"
assert_contains "default terminal plan" "$OUTPUT" "export TERMINAL=kitty"
[[ ! -e $env_file ]] && _pass || _fail "default dry-run wrote nothing"
stub systemctl "exit 0"
stub xdg-settings "exit 0"
stub xdg-mime "exit 0"
capture haseen setup default terminal kitty
assert_status "default terminal" 0 "$STATUS"
capture haseen setup default editor zed
capture haseen setup default browser zen
assert_contains "env file: terminal" "$(cat "$env_file")" "export TERMINAL=kitty"
assert_contains "env file: editor" "$(cat "$env_file")" "export EDITOR=zeditor"
assert_eq "env file: one TERMINAL line" 1 "$(grep -c '^export TERMINAL=' "$env_file")"
capture env TERMINAL=foot haseen setup default terminal
assert_eq "current terminal" "kitty" "$OUTPUT"
capture haseen setup default editor
assert_eq "current editor" "zed" "$OUTPUT"
capture haseen setup default browser
assert_eq "current browser" "zen" "$OUTPUT"
capture haseen setup default agent nope
assert_status "default rejects unknown" 1 "$STATUS"

# --- haseen setup security ---------------------------------------------------------
sandbox menu-security
ROOT="$SANDBOX/root"
mkdir -p "$ROOT/etc/pam.d"
printf '#%%PAM-1.0\nauth\t\tinclude\t\tsystem-auth\naccount\t\tinclude\t\tsystem-auth\n' >"$ROOT/etc/pam.d/sudo"
before_sum="$(b2sum "$ROOT/etc/pam.d/sudo")"
capture env HASEEN_SYSROOT="$ROOT" haseen setup fingerprint --dry-run
assert_dry_pure "fingerprint" "$OUTPUT"
assert_contains "fingerprint installs fprintd" "$OUTPUT" "DRYRUN: sudo pacman -S --needed --noconfirm fprintd"
assert_contains "fingerprint pam first" "$OUTPUT" $'    | #%PAM-1.0\n    | auth      sufficient pam_fprintd.so\n    | auth\t\tinclude'
assert_not_contains "fingerprint skips absent pam files" "$OUTPUT" "polkit-1"
assert_contains "fingerprint enrolls" "$OUTPUT" "DRYRUN: fprintd-enroll"
capture env HASEEN_SYSROOT="$ROOT" haseen setup fido2 --dry-run
assert_dry_pure "fido2" "$OUTPUT"
assert_contains "fido2 registers key" "$OUTPUT" "DRYRUN: pamu2fcfg >> $XDG_CONFIG_HOME/Yubico/u2f_keys"
assert_contains "fido2 pam" "$OUTPUT" "auth      sufficient pam_u2f.so cue"
assert_eq "pam fixture untouched" "$before_sum" "$(b2sum "$ROOT/etc/pam.d/sudo")"
capture env HASEEN_SYSROOT="$ROOT" haseen setup sshd --dry-run
assert_dry_pure "sshd" "$OUTPUT"
assert_contains "sshd key-only" "$OUTPUT" "PasswordAuthentication no"
assert_contains "sshd enabled" "$OUTPUT" "DRYRUN: sudo systemctl enable --now sshd.service"
capture env HASEEN_SYSROOT="$ROOT" haseen setup ssh-agent --dry-run
assert_dry_pure "ssh-agent" "$OUTPUT"
assert_contains "ssh-agent socket" "$OUTPUT" "DRYRUN: systemctl --user enable --now gcr-ssh-agent.socket"
capture haseen setup passwordless-sudo --dry-run
assert_dry_pure "passwordless-sudo" "$OUTPUT"
assert_contains "sudoers rule" "$OUTPUT" "$(id -un) ALL=(ALL) NOPASSWD: ALL"
assert_contains "sudoers mode" "$OUTPUT" "(mode 0440)"
capture haseen setup passwordless-sudo --off --dry-run
assert_contains "passwordless off" "$OUTPUT" "DRYRUN: sudo rm -f /etc/sudoers.d/90-haseen-$(id -un)"

# --- haseen font -----------------------------------------------------------------------
sandbox menu-font
stub fc-list 'printf "Test Mono\nTest Mono,Test Mono Alt\nNoto Color Emoji\nFoo Nerd Font Mono\n"'
capture haseen font list
assert_eq "font list filters" $'Test Mono' "$OUTPUT"
capture haseen font set "Test Mono" --dry-run
assert_dry_pure "font set" "$OUTPUT"
assert_contains "font set plan" "$OUTPUT" "DRYRUN: write $XDG_CONFIG_HOME/haseen/font:"
[[ ! -e $XDG_CONFIG_HOME/haseen/font ]] && _pass || _fail "font dry-run wrote nothing"
capture haseen font set "Missing Font"
assert_status "font set refuses missing font" 1 "$STATUS"
capture haseen font set "Test Mono"
assert_status "font set" 0 "$STATUS"
capture haseen font current
assert_eq "font current" "Test Mono" "$OUTPUT"
capture haseen font set --reset
assert_eq "font reset" "" "$(haseen font current)"

# --- haseen branding ---------------------------------------------------------------------
sandbox menu-branding
B="$XDG_CONFIG_HOME/haseen/branding"
capture haseen branding about text "Hello" --dry-run
assert_dry_pure "branding text" "$OUTPUT"
[[ ! -e $B/about.txt ]] && _pass || _fail "branding dry-run wrote nothing"
capture haseen branding about text "Hello there"
assert_eq "branding text written" "Hello there" "$(cat "$B/about.txt")"
printf 'png' >"$SANDBOX/logo.png"
capture haseen branding screensaver image "$SANDBOX/logo.png"
assert_eq "branding image copied" "png" "$(cat "$B/screensaver.png")"
capture haseen branding screensaver image "$SANDBOX/missing.png"
assert_status "branding image missing file" 1 "$STATUS"
capture haseen branding screensaver reset --dry-run
assert_contains "branding reset plan" "$OUTPUT" "DRYRUN: rm -f $B/screensaver.png"
[[ -e $B/screensaver.png ]] && _pass || _fail "branding reset dry-run removed nothing"
capture haseen branding screensaver reset
[[ ! -e $B/screensaver.png ]] && _pass || _fail "branding reset removed the image"
capture haseen branding desktop text x
assert_status "branding rejects unknown target" 2 "$STATUS"

# --- haseen config -------------------------------------------------------------------------
sandbox menu-config
stub foot "exit 0"
capture env EDITOR=nvim TERMINAL=foot haseen config edit "$HOME/.config/hypr/monitors.lua" --dry-run </dev/null
assert_dry_pure "config edit" "$OUTPUT"
assert_contains "config edit floating terminal" "$OUTPUT" "DRYRUN: foot --app-id=haseen.floating --title=haseen -e nvim $HOME/.config/hypr/monitors.lua"
[[ ! -e $HOME/.config/hypr/monitors.lua ]] && _pass || _fail "config edit dry-run created nothing"
capture env EDITOR=code haseen config edit "$HOME/x.lua" --dry-run </dev/null
assert_contains "config edit GUI editor" "$OUTPUT" "DRYRUN: setsid -f code $HOME/x.lua"
capture env TERMINAL=foot haseen config terminal --dry-run -- haseen ai status
assert_dry_pure "config terminal" "$OUTPUT"
assert_contains "config terminal argv" "$OUTPUT" "DRYRUN: foot --app-id=haseen.floating --title=haseen -e bash -c"
assert_contains "config terminal command" "$OUTPUT" "haseen ai status"

P="$XDG_CONFIG_HOME/haseen/plugins"
mkdir -p "$P/me.clock" "$XDG_CONFIG_HOME/omarchy/plugins/omarchy.thing"
ln -s "$XDG_CONFIG_HOME/omarchy/plugins/omarchy.thing" "$P/omarchy.thing"
capture haseen config plugin list-removable
assert_eq "removable: own plugins only" "me.clock" "$OUTPUT"
capture haseen config plugin remove omarchy.thing --yes
assert_status "refuses a symlinked omarchy plugin" 1 "$STATUS"
[[ -d $XDG_CONFIG_HOME/omarchy/plugins/omarchy.thing ]] && _pass || _fail "omarchy plugin kept"
capture haseen config plugin remove me.clock --dry-run
assert_contains "remove plan" "$OUTPUT" "DRYRUN: rm -rf -- $P/me.clock"
[[ -d $P/me.clock ]] && _pass || _fail "remove dry-run kept the plugin"
capture haseen config plugin remove me.clock --yes
assert_status "remove own plugin" 0 "$STATUS"
[[ ! -e $P/me.clock ]] && _pass || _fail "own plugin removed"
capture haseen config plugin add me.new bar-widget --dry-run
assert_dry_pure "plugin add" "$OUTPUT"
