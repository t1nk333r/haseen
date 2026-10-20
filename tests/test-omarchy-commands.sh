# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# haseen answers every Omarchy command but the Apple ones (plan 093).

OMA="$HASEEN_PATH/omarchy"
TABLE="$OMA/commands.tsv"
NAMES="$FIXTURES/omarchy-4.0.6/bin.txt"

# Omarchy's scripts source these three (`source omarchy-sudo-keepalive`), so
# each is a script that is safe to source whatever its kind, never a link to
# the dispatcher, which would read the sourcing script's $0.
SOURCED="omarchy-restart-gum omarchy-shell-config omarchy-sudo-keepalive"

# rows KIND... — the names of the table rows of those kinds.
rows() {
    local kinds="$*"
    awk -F'\t' -v k=" $kinds " '!/^#/ && NF >= 4 && index(k, " " $2 " ") { print $1 }' "$TABLE"
}

# --- the inventory -----------------------------------------------------------
sandbox omarchy-inventory
assert_eq "every row has four tab-separated fields" "" \
    "$(awk -F'\t' '!/^#/ && NF != 4 { print NR": "$0 }' "$TABLE")"
assert_eq "every row is one of Omarchy 4.0.6's commands" "" \
    "$(comm -23 <(awk -F'\t' '!/^#/ { print $1 }' "$TABLE" | sort) <(sort "$NAMES"))"
assert_eq "no command is listed twice" "" \
    "$(awk -F'\t' '!/^#/ { print $1 }' "$TABLE" | sort | uniq -d)"
assert_eq "every kind is one of the six" "" \
    "$(awk -F'\t' '!/^#/ && $2 !~ /^(shim|translate|port|refuse|inert|apple)$/ { print $1": "$2 }' "$TABLE")"
assert_eq "Apple hardware commands are the excluded ones" \
    "omarchy-brightness-display-apple
omarchy-hyprland-monitor-focused-apple" "$(rows apple)"

# The directory holds exactly the commands that are not Apple's: a link to
# the dispatcher for a table row, a script of its own for the rest.
assert_eq "omarchy/bin holds every non-Apple command and nothing else" \
    "$(rows shim translate port refuse inert | sort)" "$(cd "$OMA/bin" && ls | sort)"
for name in $(rows apple); do
    if [[ -e $OMA/bin/$name || -L $OMA/bin/$name ]]; then
        _fail "Apple command $name is not provided"
    else
        _pass
    fi
done
bad=""
for name in $(rows shim refuse inert); do
    [[ " $SOURCED " == *" $name "* ]] && continue
    [[ -L $OMA/bin/$name && $(readlink "$OMA/bin/$name") == ../dispatch ]] || bad+="$name "
done
assert_eq "table rows link to the dispatcher" "" "$bad"
bad=""
for name in $(rows translate port) $SOURCED; do
    [[ -f $OMA/bin/$name && ! -L $OMA/bin/$name && -x $OMA/bin/$name ]] || bad+="$name "
done
assert_eq "translations, ports and sourced helpers are executable scripts of their own" "" "$bad"
bad=""
while IFS=$'\t' read -r name kind target _; do
    [[ $kind == shim ]] || continue
    read -r cmd _ <<<"$target"
    [[ $cmd == haseen-* && -x $REPO/bin/$cmd ]] || bad+="$name→$cmd "
done < <(grep -v '^#' "$TABLE")
assert_eq "every shim names an existing haseen command" "" "$bad"
bad=""
for name in $(rows port); do
    # The notice may wrap across comment lines.
    tr -s ' \n#' ' ' <"$OMA/bin/$name" | grep -q 'MIT, Copyright (c) David Heinemeier Hansson' || bad+="$name "
done
assert_eq "every port keeps Omarchy's MIT notice" "" "$bad"
bad=""
for name in $(rows translate port); do
    [[ " $SOURCED " == *" $name "* ]] && continue
    grep -q 'omarchy/lib.sh\|/\.\./lib\.sh' "$OMA/bin/$name" || bad+="$name "
done
assert_eq "every script finds haseen through omarchy/lib.sh" "" "$bad"

# --- refusals and no-ops --------------------------------------------------------
sandbox omarchy-refuse
bad=""
for name in $(rows refuse); do
    capture "$OMA/bin/$name"
    [[ $STATUS == 1 && $OUTPUT == *"$name: not available under haseen: "* &&
        $OUTPUT == *"The haseen way: "* && $OUTPUT != *STUB-CALLED* ]] || bad+="$name($STATUS) "
done
assert_eq "every refused command says why and the haseen way, and fails" "" "$bad"
bad=""
for name in $(rows inert); do
    capture "$OMA/bin/$name"
    [[ $STATUS == 0 && $OUTPUT == *"$name: "*"(nothing to do under haseen)"* && $OUTPUT != *STUB-CALLED* ]] ||
        bad+="$name($STATUS) "
done
assert_eq "every no-op says so and succeeds" "" "$bad"

# Every command answers --help without running anything.
bad=""
for name in $(rows shim translate port refuse inert); do
    capture "$OMA/bin/$name" --help
    [[ $STATUS == 0 && -n $OUTPUT && $OUTPUT != *STUB-CALLED* ]] || bad+="$name($STATUS) "
done
assert_eq "every command takes --help" "" "$bad"

# Sourced, each keeps its contract without leaking haseen's helpers into the
# sourcing script.
sandbox omarchy-sourced
capture bash -c 'source "$1"; echo "after: $?"' _ "$OMA/bin/omarchy-restart-gum"
assert_eq "sourced restart-gum changes nothing and says nothing" "after: 0" "$OUTPUT"
capture bash -c 'source "$1"; echo after' _ "$OMA/bin/omarchy-shell-config"
assert_status "sourced shell-config stops the sourcing script" 1 "$STATUS"
assert_contains "sourced shell-config says why" "$OUTPUT" "Omarchy's ~/.config/omarchy/shell.json"
assert_not_contains "nothing after it runs" "$OUTPUT" "after"
capture env DRY_RUN=true bash -c 'source "$1"; echo "after: ${SUDO_KEEPALIVE_PID:-none}"; type run_root >/dev/null 2>&1 && echo leaked' _ "$OMA/bin/omarchy-sudo-keepalive"
assert_dry_pure "sourced sudo-keepalive" "$OUTPUT"
assert_contains "sourced sudo-keepalive asks sudo through common.sh" "$OUTPUT" "DRYRUN: sudo -v"
assert_contains "a dry run starts no keepalive" "$OUTPUT" "after: none"
assert_not_contains "common.sh's helpers stay out of the sourcing shell" "$OUTPUT" "leaked"
stub sudo 'echo "sudo $*" >>"'"$SANDBOX"'/sudo.log"; exit 0'
capture bash -c 'source "$1"; echo "pid=${SUDO_KEEPALIVE_PID:-none}"' _ "$OMA/bin/omarchy-sudo-keepalive"
assert_contains "sourced sudo-keepalive keeps sudo alive in the background" "$OUTPUT" "pid="
assert_not_contains "with a keepalive PID" "$OUTPUT" "pid=none"
assert_contains "after asking for the password once" "$(cat "$SANDBOX/sudo.log")" "sudo -v"

# --- the router ---------------------------------------------------------------
sandbox omarchy-router
FAKE="$SANDBOX/fake"
mkdir -p "$FAKE/bin" "$FAKE/share/haseen"
ln -s "$HASEEN_PATH/lib" "$FAKE/share/haseen/lib"
ln -s "$HASEEN_PATH/omarchy" "$FAKE/share/haseen/omarchy"
for t in haseen-update haseen-capture-screenshot haseen-system haseen-theme-bg haseen-theme-set; do
    printf '#!/bin/sh\nprintf %%s "${0##*/}"; for a in "$@"; do printf " [%%s]" "$a"; done; echo\n' >"$FAKE/bin/$t"
    chmod +x "$FAKE/bin/$t"
done
omarchy() { env HASEEN_PATH="$FAKE/share/haseen" "$OMA/bin/omarchy" "$@"; }
capture omarchy update -y
assert_eq "omarchy update routes to omarchy-update" "haseen-update [-y]" "$OUTPUT"
capture omarchy theme set nord
assert_eq "the longest command name wins" "haseen-theme-set [nord]" "$OUTPUT"
capture omarchy
assert_status "bare omarchy prints help" 0 "$STATUS"
assert_contains "bare omarchy says haseen answers" "$OUTPUT" "answered by haseen"
capture omarchy commands
assert_contains "omarchy commands lists the adopted commands" "$OUTPUT" "omarchy-update"
assert_not_contains "omarchy commands leaves out Apple's" "$OUTPUT" "omarchy-brightness-display-apple"
capture omarchy commands --all
assert_contains "omarchy commands --all names Apple's" "$OUTPUT" "omarchy-brightness-display-apple"
capture omarchy capture
assert_status "a group lists its commands" 0 "$STATUS"
assert_contains "a group lists its commands" "$OUTPUT" "omarchy-capture-screenrecording"
capture omarchy no-such-thing
assert_status "an unknown command exits 127, as Omarchy's router does" 127 "$STATUS"
assert_dry_pure "router" "$OUTPUT"

# --- installed ahead of Omarchy's, removed again --------------------------------
sandbox omarchy-install
prefix="$SANDBOX/prefix"
mkdir -p "$prefix/bin"
capture env HASEEN_SYSROOT="$FIXTURES/cachyos-grub-plain" "$REPO/install.sh" --dry-run --tree-only --prefix "$prefix"
assert_status "install tree dry-run" 0 "$STATUS"
assert_dry_pure "install links" "$OUTPUT"
link_line="$(grep -F "DRYRUN: sudo ln -sf -t $prefix/bin " <<<"$OUTPUT" || true)"
assert_contains "one ln links the commands into PREFIX/bin" "$link_line" \
    " ../share/haseen/omarchy/bin/omarchy-update "
assert_contains "the router is linked too" "$link_line" " ../share/haseen/omarchy/bin/omarchy "
assert_eq "every command in omarchy/bin is linked" "$(ls "$OMA/bin" | wc -l)" \
    "$(tr ' ' '\n' <<<"$link_line" | grep -c '^\.\./share/haseen/omarchy/bin/')"
assert_not_contains "Apple commands are not linked" "$link_line" "-apple"

# A second install keeps haseen's links, drops a stale one, never touches a
# file that is not haseen's link.
ln -s ../share/haseen/omarchy/bin/omarchy-update "$prefix/bin/omarchy-update"
ln -s ../share/haseen/omarchy/bin/omarchy-retired "$prefix/bin/omarchy-retired"
printf '#!/bin/sh\n' >"$prefix/bin/omarchy-theme-set"
ln -s /usr/bin/omarchy-menu "$prefix/bin/omarchy-menu"
capture env HASEEN_SYSROOT="$FIXTURES/cachyos-grub-plain" "$REPO/install.sh" --dry-run --tree-only --prefix "$prefix"
link_line="$(grep -F "DRYRUN: sudo ln -sf -t $prefix/bin " <<<"$OUTPUT" || true)"
assert_not_contains "an existing haseen link is left as it is" "$link_line" "/omarchy-update "
assert_not_contains "a foreign file is not replaced" "$link_line" "/omarchy-theme-set "
assert_not_contains "a foreign link is not replaced" "$link_line" "/omarchy-menu "
assert_contains "the foreign file is named" "$OUTPUT" "$prefix/bin/omarchy-theme-set is not haseen's"
assert_contains "a link to a retired command is removed" "$OUTPUT" "DRYRUN: sudo rm -f $prefix/bin/omarchy-retired"
capture env HASEEN_SYSROOT="$FIXTURES/cachyos-grub-plain" "$REPO/install.sh" --dry-run --uninstall-tree --prefix "$prefix"
assert_status "uninstall dry-run" 0 "$STATUS"
assert_contains "uninstall removes haseen's links" "$OUTPUT" \
    "DRYRUN: sudo rm -f $prefix/bin/omarchy-retired $prefix/bin/omarchy-update"
assert_not_contains "uninstall keeps a foreign file" "$OUTPUT" "$prefix/bin/omarchy-theme-set"
assert_not_contains "uninstall keeps a foreign link" "$OUTPUT" "$prefix/bin/omarchy-menu"

# --- the shell restart never starts Omarchy's shell -----------------------------
# IO (plan 093): `omarchy-update` → omarchy-update-restart →
# omarchy-restart-shell → `hyprctl dispatch exec_cmd omarchy-launch-shell`
# started Omarchy's shell beside haseen's. A directory of fake Omarchy
# commands stands in for /usr/bin, after haseen's on PATH as on IO, where
# /usr/local/bin comes first; the fake launcher logs if it is ever reached.
sandbox omarchy-restart
LOG="$SANDBOX/calls.log"
: >"$LOG"
USRBIN="$SANDBOX/omarchy-usr-bin"
mkdir -p "$USRBIN"
printf '#!/bin/sh\necho "OMARCHY SHELL LAUNCHED" >>"%s"\n' "$LOG" >"$USRBIN/omarchy-launch-shell"
# Omarchy 4.0.6's restart, reduced to its last step (omarchy-restart-shell:91).
printf '#!/bin/sh\nhyprctl dispatch '\''hl.dsp.exec_cmd("omarchy-launch-shell")'\''\n' >"$USRBIN/omarchy-restart-shell"
chmod +x "$USRBIN"/*
# Hyprland runs an exec_cmd through its own PATH.
stub hyprctl 'echo "hyprctl $*" >>"'"$LOG"'"; cmd=$(printf "%s" "$2" | sed -n "s/.*exec_cmd(\"\(.*\)\").*/\1/p"); [ -n "$cmd" ] && exec sh -c "$cmd"; exit 0'
# One Omarchy shell (pid 4242) beside haseen's.
stub qs 'case "$1" in
list) printf "[{\"config_path\":\"/usr/share/omarchy/shell/shell.qml\",\"pid\":4242},{\"config_path\":\"%s/shell/shell.qml\",\"pid\":7}]\n" "$HASEEN_PATH" ;;
kill) echo "qs $*" >>"'"$LOG"'" ;;
*) echo "STUB-CALLED: qs $*" >&2; exit 97 ;;
esac'
# haseen-shell.service is installed but not running.
stub systemctl 'case "$*" in
"--user is-active --quiet haseen-shell.service") exit 3 ;;
"--user cat haseen-shell.service") exit 0 ;;
*) echo "systemctl $*" >>"'"$LOG"'" ;;
esac'
unset OMARCHY_PATH
OPATH="$OMA/bin:$USRBIN:$PATH"
capture env PATH="$OPATH" "$USRBIN/omarchy-restart-shell"
assert_status "Omarchy's own restart reaches haseen's launcher" 0 "$STATUS"
calls="$(<"$LOG")"
assert_not_contains "Omarchy's launcher never runs" "$calls" "OMARCHY SHELL LAUNCHED"
assert_contains "the running Omarchy shell is stopped" "$calls" "qs kill --pid 4242"
assert_not_contains "haseen's own instance is left alone" "$calls" "qs kill --pid 7"
assert_contains "haseen's shell unit is started" "$calls" "systemctl --user start haseen-shell.service"

# haseen's restart: the Omarchy shell goes, haseen's unit restarts.
stub systemctl 'case "$*" in
"--user is-active --quiet haseen-shell.service") exit 0 ;;
*) echo "STUB-CALLED: systemctl $*" >&2; exit 97 ;;
esac'
capture env PATH="$OPATH" DRY_RUN=true omarchy-restart-shell
assert_status "restart dry-run" 0 "$STATUS"
assert_dry_pure "restart" "$OUTPUT"
assert_contains "restart stops Omarchy's shell" "$OUTPUT" "DRYRUN: qs kill --pid 4242"
assert_contains "restart restarts haseen's unit" "$OUTPUT" "DRYRUN: systemctl --user restart haseen-shell.service"
capture env PATH="$OPATH" omarchy-restart-shell --dry-run
assert_contains "--dry-run works as the flag too" "$OUTPUT" "DRYRUN: systemctl --user restart haseen-shell.service"

# Launch with haseen's unit running: nothing to start.
capture env PATH="$OPATH" DRY_RUN=true omarchy-launch-shell
assert_status "launch dry-run" 0 "$STATUS"
assert_dry_pure "launch" "$OUTPUT"
assert_contains "launch says the haseen shell runs" "$OUTPUT" "already running (haseen-shell.service)"
assert_not_contains "launch starts nothing more" "$OUTPUT" "systemctl --user start"

# No unit: a running qs instance of haseen's shell counts; without one the
# shell runs in the foreground, as Omarchy's launcher keeps its own.
stub systemctl 'exit 3'
capture env PATH="$OPATH" DRY_RUN=true omarchy-launch-shell
assert_contains "launch without a unit sees haseen's qs instance" "$OUTPUT" "already running (qs -p"
stub qs 'case "$1" in list) echo "[]" ;; *) echo "STUB-CALLED: qs $*" >&2; exit 97 ;; esac'
capture env PATH="$OPATH" DRY_RUN=true omarchy-launch-shell
assert_contains "launch without unit or instance runs haseen shell run" "$OUTPUT" "DRYRUN: $REPO/share/haseen/../../bin/haseen-shell-run"
assert_dry_pure "launch without a unit" "$OUTPUT"

# DMS chosen with haseen shell use: that is the shell to (re)start.
mkdir -p "$XDG_STATE_HOME/haseen"
echo dms >"$XDG_STATE_HOME/haseen/active-shell"
capture env PATH="$OPATH" DRY_RUN=true omarchy-restart-shell
assert_contains "restart under DMS restarts dms.service" "$OUTPUT" "DRYRUN: systemctl --user restart dms.service"
capture env PATH="$OPATH" DRY_RUN=true omarchy-launch-shell
assert_contains "launch under DMS starts dms.service" "$OUTPUT" "DRYRUN: systemctl --user start dms.service"
rm "$XDG_STATE_HOME/haseen/active-shell"

# The update's last step: a reboot is offered only for a replaced kernel, and
# the shell restarted is haseen's.
ROOT="$SANDBOX/root"
mkdir -p "$ROOT/usr/lib/modules/6.9.1-test"
: >"$ROOT/usr/lib/modules/6.9.1-test/vmlinuz"
stub uname 'echo 6.9.1-test'
stub systemctl 'case "$*" in "--user is-active --quiet haseen-shell.service") exit 0 ;; *) echo "STUB-CALLED: systemctl $*" >&2; exit 97 ;; esac'
capture env PATH="$OPATH" HASEEN_SYSROOT="$ROOT" omarchy-update-restart --dry-run
assert_status "update-restart dry-run" 0 "$STATUS"
assert_dry_pure "update-restart" "$OUTPUT"
assert_not_contains "the running kernel is still installed: no reboot offered" "$OUTPUT" "Reboot?"
assert_contains "update-restart restarts haseen's shell" "$OUTPUT" "DRYRUN: systemctl --user restart haseen-shell.service"
stub uname 'echo 6.8.0-old'
capture env PATH="$OPATH" HASEEN_SYSROOT="$ROOT" omarchy-update-restart --dry-run
assert_contains "a replaced kernel offers a reboot" "$OUTPUT" "DRYRUN: ask 'Linux kernel has been updated. Reboot?'"
capture env PATH="$OPATH" HASEEN_SYSROOT="$ROOT" omarchy-update-restart </dev/null
assert_contains "without a terminal the reboot is not asked" "$OUTPUT" "not asked: no terminal"
assert_not_contains "and not done" "$OUTPUT" "haseen-system"

# --- omarchy-shell: Omarchy's IPC verbs on haseen's shell -----------------------
sandbox omarchy-shell-ipc
FAKE="$SANDBOX/fake"
mkdir -p "$FAKE/bin" "$FAKE/share/haseen"
for d in lib omarchy shell; do ln -s "$HASEEN_PATH/$d" "$FAKE/share/haseen/$d"; done
# A recording haseen command logs its name and arguments in brackets to
# $CALLS; the fake IPC answers `shell plugins` from $IPC_PLUGINS and fails
# with $IPC_RC.
export CALLS="$SANDBOX/calls"
for t in haseen-menu haseen-plugin-enable haseen-plugin-disable haseen-bar-add haseen-bar-transparent; do
    printf '#!/bin/sh\n{ printf %%s "${0##*/}"; for a in "$@"; do printf " [%%s]" "$a"; done; echo; } >>"$CALLS"\n' >"$FAKE/bin/$t"
done
cat >"$FAKE/bin/haseen-shell-ipc" <<'IPC'
#!/bin/sh
[ -n "$IPC_RC" ] && exit "$IPC_RC"
if [ "$1 $2" = "shell plugins" ]; then printf '%s\n' "$IPC_PLUGINS"; exit 0; fi
printf 'ipc'; for a in "$@"; do printf ' [%s]' "$a"; done; echo
IPC
chmod +x "$FAKE/bin"/*
oshell() { env HASEEN_PATH="$FAKE/share/haseen" "$OMA/bin/omarchy-shell" "$@"; }
export IPC_PLUGINS='{"ready":true,"plugins":[{"id":"haseen.clock","name":"Clock","kinds":["bar-widget"],"enabled":true,"origin":"builtin"},{"id":"t1nk33r.updates","name":"Updates","enabled":false,"origin":"user:omarchy"}]}'
capture oshell
assert_status "omarchy-shell without arguments prints usage" 0 "$STATUS"
capture oshell shell
assert_status "one argument is too few" 1 "$STATUS"
capture oshell shell ping
assert_eq "ping answers ok once the shell has loaded" "ok" "$OUTPUT"
IPC_PLUGINS='{"ready":false}' capture oshell shell ping
assert_status "ping fails while the shell loads" 1 "$STATUS"
assert_contains "and says so" "$OUTPUT" "not ready"
IPC_RC=1 capture oshell shell ping
assert_contains "no shell: not running" "$OUTPUT" "haseen's shell is not running"
IPC_RC=1 capture oshell -q shell ping
assert_status "-q never fails" 0 "$STATUS"
assert_eq "-q prints nothing" "" "$OUTPUT"
capture oshell shell toggle omarchy.menu '{"menu":"setup"}'
assert_eq "omarchy.menu answers ok" "ok" "$OUTPUT"
assert_eq "omarchy.menu opens haseen's menu at the route" "haseen-menu [setup]" "$(tail -n1 "$CALLS")"
capture oshell shell summon omarchy.menu '{"menu":"root"}'
assert_eq "the root route is the top level" "haseen-menu" "$(tail -n1 "$CALLS")"
capture oshell shell toggle omarchy.weather
assert_eq "an Omarchy built-in opens haseen's own panel" "ok" "$OUTPUT"
capture oshell shell toggle omarchy.launcher
assert_eq "the launcher is a role, not a panel" "ok" "$OUTPUT"
capture oshell shell call t1nk33r.updates refresh
assert_eq "call reaches the plugin's own target" "ipc [t1nk33r.updates] [refresh]" "$OUTPUT"
capture oshell t1nk33r.updates refresh
assert_eq "other targets pass through" "ipc [t1nk33r.updates] [refresh]" "$OUTPUT"
capture oshell shell listPlugins
assert_eq "listPlugins answers in Omarchy's shape" \
    '[{"id":"haseen.clock","name":"Clock","kinds":["bar-widget"],"enabled":true,"active":false,"canDisable":true,"firstParty":true,"clonedFrom":""},{"id":"t1nk33r.updates","name":"Updates","kinds":[],"enabled":false,"active":false,"canDisable":true,"firstParty":false,"clonedFrom":""}]' \
    "$OUTPUT"
capture oshell shell setPluginEnabled t1nk33r.updates true
assert_eq "setPluginEnabled true is haseen plugin enable" "haseen-plugin-enable [t1nk33r.updates]" "$(tail -n1 "$CALLS")"
capture oshell shell setPluginEnabled t1nk33r.updates false
assert_eq "setPluginEnabled false is haseen plugin disable" "haseen-plugin-disable [t1nk33r.updates]" "$(tail -n1 "$CALLS")"
capture oshell shell putBarWidget t1nk33r.updates '{"section":"right","before":"haseen.clock"}'
assert_eq "putBarWidget answers ok" "ok" "$OUTPUT"
assert_eq "putBarWidget is haseen bar add" "haseen-bar-add [t1nk33r.updates] [right] [--before] [haseen.clock]" "$(tail -n1 "$CALLS")"
capture oshell shell enablePlugin t1nk33r.updates
assert_eq "enablePlugin without a section is haseen plugin enable" "haseen-plugin-enable [t1nk33r.updates]" "$(tail -n1 "$CALLS")"
capture oshell shell applyTheme x y
assert_status "an Omarchy-only verb is not found" 1 "$STATUS"
assert_contains "an Omarchy-only verb is not found" "$OUTPUT" "Function not found."
export HYPRLAND_INSTANCE_SIGNATURE=sig-a
printf '1 sig-a\n' >"$XDG_RUNTIME_DIR/haseen-lock-held"
stub hyprctl 'exit 1'
capture oshell lock status
assert_eq "lock status from haseen's lock marker" \
    '{"locked":true,"requested":true,"pending":false,"sessionLocked":false,"secure":false}' "$OUTPUT"
capture oshell lock isLocked
assert_eq "isLocked follows the marker" "true" "$OUTPUT"
printf '1 sig-other\n' >"$XDG_RUNTIME_DIR/haseen-lock-held"
capture oshell lock isLocked
assert_eq "another instance's marker is not this session's lock" "false" "$OUTPUT"
unset HYPRLAND_INSTANCE_SIGNATURE
assert_dry_pure "omarchy-shell" "$OUTPUT"
