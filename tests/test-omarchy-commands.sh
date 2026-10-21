# shellcheck shell=bash
# haseen:covers bin/haseen-* share/haseen/VERSION share/haseen/branding/**
# haseen:covers share/haseen/default/applications/** share/haseen/default/shell.json
# haseen:covers share/haseen/default/shell/init.sh share/haseen/default/xdg-terminal-exec/**
# haseen:covers share/haseen/layers/{base,chaotic,desktop,omarchy-repo,shell,theme}/layer.sh
# haseen:covers share/haseen/layers/base/lib.sh share/haseen/layers/gaming/layer.sh
# haseen:covers share/haseen/layers/theme/theme-lib.sh
# haseen:covers share/haseen/lib/{boot,branding,cairn,catalog,doctor,greeter,hardware,hibernate}.sh
# haseen:covers share/haseen/lib/{install-picker,layers,ledger,migrate,omarchy-import,packages}.sh
# haseen:covers share/haseen/lib/{plymouth,preflight,screen,shellrc,terminal}.sh
# haseen:covers share/haseen/migrations/1792531693-omarchy-path.sh share/haseen/omarchy/**
# haseen:covers share/haseen/shell/lib/{plugin,registry}.sh share/haseen/systemd/user/**
# haseen:covers tests/fixtures/{cachyos-grub-plain,omarchy-4.0.6}/** tools/build-sidecar.sh
# haseen:covers install.sh plans/093-adopt-omarchy-commands.md
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
assert_eq "the table lists exactly Omarchy 4.0.6's 446 commands" \
    "$(sort "$NAMES")" "$(awk -F'\t' '!/^#/ { print $1 }' "$TABLE" | sort)"
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
bad=""
for name in $(rows shim translate port refuse inert apple); do
    grep -qF "| \`$name\` |" "$REPO/plans/093-adopt-omarchy-commands.md" || bad+="$name "
done
assert_eq "plan 093's inventory lists every command" "" "$bad"

# --- refusals and no-ops --------------------------------------------------------
sandbox omarchy-refuse
bad=""
for name in $(rows refuse); do
    capture "$OMA/bin/$name"
    [[ $STATUS == 1 && $OUTPUT == *"$name: not available under haseen."* &&
        $(wc -l <<<"$OUTPUT") -ge 3 && $OUTPUT != *STUB-CALLED* &&
        ($OUTPUT == *"The haseen way: "* || $OUTPUT == *"No haseen equivalent: "*) ]] || bad+="$name($STATUS) "
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

# A real install and uninstall into a scratch PREFIX, the install twice. sudo
# runs the command as the user (the PREFIX is the sandbox's); a no-op go and a
# cargo that does not run keep the sidecar and wootingd builds out of the
# checkout.
sandbox omarchy-install-real
stub sudo 'exec "$@"'
stub go 'exit 0'
stub cargo 'exit 1'
prefix="$SANDBOX/prefix"
mkdir -p "$prefix/bin"
printf 'foreign\n' >"$prefix/bin/omarchy-theme-set"
ln -s /usr/bin/true "$prefix/bin/omarchy-menu"
# haseen_links — every haseen omarchy link in PREFIX/bin, with its target.
haseen_links() {
    find "$prefix/bin" -maxdepth 1 -lname '../share/haseen/omarchy/bin/*' -printf '%f %l\n' | LC_ALL=C sort
}
install_real() {
    capture env HASEEN_SYSROOT="$FIXTURES/cachyos-grub-plain" "$REPO/install.sh" --tree-only --yes --prefix "$prefix" </dev/null
}
install_real
assert_status "a real tree install succeeds" 0 "$STATUS"
assert_contains "it warns about the foreign file" "$OUTPUT" "$prefix/bin/omarchy-theme-set is not haseen's and stays"
assert_contains "and the foreign link" "$OUTPUT" "$prefix/bin/omarchy-menu is not haseen's and stays"
assert_eq "every other command is linked" "$(($(ls "$OMA/bin" | wc -l) - 2))" "$(haseen_links | wc -l)"
assert_eq "a link reaches the installed command" "$prefix/share/haseen/omarchy/bin/omarchy-launch-shell" \
    "$(readlink -f "$prefix/bin/omarchy-launch-shell")"
capture "$prefix/bin/omarchy-update" --help
assert_status "and runs from PREFIX/bin" 0 "$STATUS"
assert_eq "the foreign file is untouched" "foreign" "$(cat "$prefix/bin/omarchy-theme-set")"
assert_eq "the foreign link is untouched" "/usr/bin/true" "$(readlink "$prefix/bin/omarchy-menu")"
first="$(haseen_links)"
install_real
assert_status "a second install succeeds" 0 "$STATUS"
assert_eq "and changes no link" "$first" "$(haseen_links)"
assert_eq "the foreign file is still untouched" "foreign" "$(cat "$prefix/bin/omarchy-theme-set")"
capture env HASEEN_SYSROOT="$FIXTURES/cachyos-grub-plain" "$REPO/install.sh" --uninstall-tree --yes --prefix "$prefix" </dev/null
assert_status "a real uninstall succeeds" 0 "$STATUS"
assert_eq "it removes every haseen link" "" "$(haseen_links)"
assert_eq "and keeps the foreign file" "foreign" "$(cat "$prefix/bin/omarchy-theme-set")"
assert_eq "and the foreign link" "/usr/bin/true" "$(readlink "$prefix/bin/omarchy-menu")"
assert_eq "and removes the tree" "no" "$([[ -e $prefix/share/haseen ]] && echo yes || echo no)"

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
# Quickshell 0.3.2's argument rules, as on luna: `qs list -a` and `qs kill
# --pid` each exit 108 with --any-display. The stub lists the instances in
# $QS_JSON and logs every kill; QS_FAIL=1 makes the listing fail.
QS_JSON="$SANDBOX/qs.json"
stub qs 'case "$1" in
list)
    case " $* " in *" --any-display "*) case " $* " in *" -a "*|*" --all "*)
        echo "[Option Group: Config Selection] excludes --all" >&2; exit 108 ;; esac ;; esac
    [ -z "$QS_FAIL" ] || { echo "qs: cannot read the instance directory" >&2; exit 1; }
    cat "'"$QS_JSON"'" ;;
kill)
    case " $* " in *" --pid "*) case " $* " in *" --any-display "*|*" -p "*|*" --path "*)
        echo "[Option Group: Instance Selection] excludes [Option Group: Config Selection]" >&2; exit 108 ;; esac ;; esac
    echo "qs $*" >>"'"$LOG"'" ;;
*) echo "STUB-CALLED: qs $*" >&2; exit 97 ;;
esac'
omarchy_instance='{"config_path":"/usr/share/omarchy/shell/shell.qml","pid":4242}'
haseen_instance="{\"config_path\":\"$HASEEN_PATH/shell/shell.qml\",\"pid\":7}"
# One Omarchy shell (pid 4242) beside haseen's.
echo "[$omarchy_instance,$haseen_instance]" >"$QS_JSON"
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
# A listing failure is reported, and haseen's own shell still restarts.
capture env PATH="$OPATH" DRY_RUN=true QS_FAIL=1 omarchy-restart-shell
assert_status "restart goes on when qs cannot list instances" 0 "$STATUS"
assert_contains "and says an Omarchy shell was not stopped" "$OUTPUT" "an Omarchy shell, if one runs, was not stopped"
assert_contains "and restarts haseen's unit" "$OUTPUT" "DRYRUN: systemctl --user restart haseen-shell.service"
# An OMARCHY_PATH that names haseen's own tree never makes haseen's shell
# "Omarchy's".
capture env PATH="$OPATH" DRY_RUN=true OMARCHY_PATH="$HASEEN_PATH" omarchy-restart-shell
assert_not_contains "haseen's shell is never stopped as Omarchy's" "$OUTPUT" "qs kill --pid 7"

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
assert_contains "and still stops the Omarchy shell beside it" "$OUTPUT" "DRYRUN: qs kill --pid 4242"
assert_not_contains "and starts no second haseen shell" "$OUTPUT" "haseen-shell-run"
# Only haseen's instance: nothing to stop, nothing to start.
echo "[$haseen_instance]" >"$QS_JSON"
capture env PATH="$OPATH" DRY_RUN=true omarchy-launch-shell
assert_contains "launch with only haseen's instance sees it" "$OUTPUT" "already running (qs -p"
assert_not_contains "and stops nothing" "$OUTPUT" "qs kill"
# Only an Omarchy shell: it is stopped and haseen's runs in its place.
echo "[$omarchy_instance]" >"$QS_JSON"
capture env PATH="$OPATH" DRY_RUN=true omarchy-launch-shell
assert_contains "launch with only Omarchy's shell stops it" "$OUTPUT" "DRYRUN: qs kill --pid 4242"
assert_contains "and runs haseen's in the foreground" "$OUTPUT" "DRYRUN: $REPO/share/haseen/../../bin/haseen-shell-run"
echo "[]" >"$QS_JSON"
capture env PATH="$OPATH" DRY_RUN=true omarchy-launch-shell
assert_contains "launch without unit or instance runs haseen shell run" "$OUTPUT" "DRYRUN: $REPO/share/haseen/../../bin/haseen-shell-run"
assert_dry_pure "launch without a unit" "$OUTPUT"
# Quickshell cannot list its instances: launching could start a second
# haseen shell, so it stops and says why.
capture env PATH="$OPATH" DRY_RUN=true QS_FAIL=1 omarchy-launch-shell
assert_status "launch refuses when qs cannot list instances" 1 "$STATUS"
assert_contains "and says qs failed" "$OUTPUT" "could not list Quickshell instances"
assert_not_contains "and starts nothing" "$OUTPUT" "haseen-shell-run"

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

# Under haseen's lock screen the shell is not restarted (it draws the lock),
# and the update still finishes, as Omarchy's does.
stub uname 'echo 6.9.1-test'
export HYPRLAND_INSTANCE_SIGNATURE=sig-a
printf '1 sig-a\n' >"$XDG_RUNTIME_DIR/haseen-lock-held"
capture env PATH="$OPATH" DRY_RUN=true omarchy-restart-shell
assert_status "restart refuses under the lock screen" 1 "$STATUS"
assert_contains "and says why" "$OUTPUT" "the session is locked; the shell is not restarted"
assert_not_contains "and restarts nothing" "$OUTPUT" "systemctl --user restart"
assert_not_contains "and stops nothing" "$OUTPUT" "qs kill"
capture env PATH="$OPATH" HASEEN_SYSROOT="$ROOT" omarchy-update-restart --dry-run
assert_status "the update still finishes" 0 "$STATUS"
assert_contains "and says the shell was not restarted" "$OUTPUT" "the desktop shell was not restarted"
printf '1 sig-other\n' >"$XDG_RUNTIME_DIR/haseen-lock-held"
capture env PATH="$OPATH" DRY_RUN=true omarchy-restart-shell
assert_contains "another Hyprland instance's lock does not hold this one" "$OUTPUT" "DRYRUN: systemctl --user restart haseen-shell.service"
printf '0\n' >"$XDG_RUNTIME_DIR/haseen-lock-held"
capture env PATH="$OPATH" DRY_RUN=true omarchy-restart-shell
assert_contains "a released lock restarts" "$OUTPUT" "DRYRUN: systemctl --user restart haseen-shell.service"
# From a TTY (no signature): a marker whose instance still runs holds.
unset HYPRLAND_INSTANCE_SIGNATURE
printf '1 sig-a\n' >"$XDG_RUNTIME_DIR/haseen-lock-held"
mkdir -p "$XDG_RUNTIME_DIR/hypr/sig-a"
capture env PATH="$OPATH" DRY_RUN=true omarchy-restart-shell
assert_status "from a TTY a live instance's lock holds" 1 "$STATUS"
rmdir "$XDG_RUNTIME_DIR/hypr/sig-a"
capture env PATH="$OPATH" DRY_RUN=true omarchy-restart-shell
assert_contains "a stale marker from a gone instance does not" "$OUTPUT" "DRYRUN: systemctl --user restart haseen-shell.service"
rm -f "$XDG_RUNTIME_DIR/haseen-lock-held"

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

# --- haseen's answers come first on every PATH (plan 093) ------------------------
# luna's Hyprland PATH (/proc/<Hyprland>/environ, 2026-10-20) has
# /usr/share/omarchy/bin before /usr/local/bin: its Omarchy-seeded
# ~/.config/uwsm/env prepends $OMARCHY_PATH/bin. IO's starts
# /usr/local/sbin:/usr/local/bin:/usr/bin after the user's own dirs.
sandbox omarchy-path
ROOT="$SANDBOX/root"
for d in /usr/share/omarchy/bin /usr/bin /usr/local/share/haseen/omarchy/bin /usr/local/bin "$HASEEN_PATH/omarchy/bin"; do
    mkdir -p "$ROOT$d"
done
for d in /usr/share/omarchy/bin /usr/bin /usr/local/share/haseen/omarchy/bin "$HASEEN_PATH/omarchy/bin"; do
    printf '#!/bin/sh\n' >"$ROOT$d/omarchy-launch-shell"
    chmod +x "$ROOT$d/omarchy-launch-shell"
done
ln -s ../share/haseen/omarchy/bin/omarchy-launch-shell "$ROOT/usr/local/bin/omarchy-launch-shell"
# doctor_fn FUNCTION ARGS... — a lib/doctor.sh function against the sysroot.
doctor_fn() {
    capture env HASEEN_SYSROOT="$ROOT" bash -c \
        'source "$HASEEN_PATH/lib/common.sh"; source "$HASEEN_PATH/lib/doctor.sh"; "$@"' _ "$@"
}
doctor_fn doctor_omarchy_path compositor "/opt/x:/usr/share/omarchy/bin:/usr/local/sbin:/usr/local/bin:/usr/bin" "fix it"
assert_status "luna's order fails the doctor" 1 "$STATUS"
assert_contains "and names Omarchy's directory" "$OUTPUT" "compositor omarchy commands=FAIL: /usr/share/omarchy/bin/omarchy-launch-shell comes before haseen's"
assert_contains "and how to fix it" "$OUTPUT" "; fix it"
doctor_fn doctor_omarchy_path compositor "/opt/x:/usr/local/sbin:/usr/local/bin:/usr/bin" "fix it"
assert_status "IO's order passes" 0 "$STATUS"
assert_eq "through PREFIX/bin's link" "compositor omarchy commands=haseen's (/usr/local/bin)" "$OUTPUT"
doctor_fn doctor_omarchy_path terminal "$HASEEN_PATH/omarchy/bin:/usr/share/omarchy/bin:/usr/bin" "fix it"
assert_eq "haseen's own omarchy/bin first passes" "terminal omarchy commands=haseen's ($HASEEN_PATH/omarchy/bin)" "$OUTPUT"
doctor_fn doctor_omarchy_path terminal "/opt/x:/opt/y" "fix it"
assert_eq "no omarchy command anywhere is no failure" "terminal omarchy commands=none on its PATH" "$OUTPUT"

# The compositor's PATH comes from Hyprland's lock file and environ.
mkdir -p "$ROOT$XDG_RUNTIME_DIR/hypr/old" "$ROOT$XDG_RUNTIME_DIR/hypr/new" "$ROOT/proc/4321"
printf '1111\nwayland-0\n' >"$ROOT$XDG_RUNTIME_DIR/hypr/old/hyprland.lock"
touch -d '1 hour ago' "$ROOT$XDG_RUNTIME_DIR/hypr/old/hyprland.lock"
printf '4321\nwayland-1\n' >"$ROOT$XDG_RUNTIME_DIR/hypr/new/hyprland.lock"
printf 'HOME=/home/x\0PATH=/usr/share/omarchy/bin:/usr/local/bin:/usr/bin\0SHELL=/bin/bash\0' >"$ROOT/proc/4321/environ"
doctor_fn doctor_hyprland_pid
assert_eq "without a signature the newest instance's pid" "4321" "$OUTPUT"
capture env HASEEN_SYSROOT="$ROOT" HYPRLAND_INSTANCE_SIGNATURE=old bash -c \
    'source "$HASEEN_PATH/lib/common.sh"; source "$HASEEN_PATH/lib/doctor.sh"; doctor_hyprland_pid'
assert_eq "this session's instance when the signature names it" "1111" "$OUTPUT"
doctor_fn doctor_environ_path "$ROOT/proc/4321/environ"
assert_eq "the PATH from Hyprland's environ" "/usr/share/omarchy/bin:/usr/local/bin:/usr/bin" "$OUTPUT"
doctor_fn doctor_environ_path "$ROOT/proc/9999/environ"
assert_status "an unreadable environ fails" 1 "$STATUS"
rm -r "$ROOT$XDG_RUNTIME_DIR/hypr"
doctor_fn doctor_hyprland_pid
assert_status "no Hyprland instance fails" 1 "$STATUS"

# The fix: the desktop layer's uwsm fragment, sourced after an
# Omarchy-seeded ~/.config/uwsm/env (uwsm's order: env, then env.d/*, in each
# config directory), puts haseen's commands first for the whole session.
capture env HASEEN_PATH="$HASEEN_PATH" bash -c \
    'source "$HASEEN_PATH/lib/common.sh"; source "$HASEEN_PATH/layers/desktop/layer.sh"; desktop_session_env'
printf '%s\n' "$OUTPUT" >"$SANDBOX/10-haseen"
printf 'export OMARCHY_PATH="${OMARCHY_PATH:-/usr/share/omarchy}"\nexport PATH=$OMARCHY_PATH/bin:$PATH\n' >"$SANDBOX/uwsm-env"
session_path="$(env -i PATH=/usr/local/sbin:/usr/local/bin:/usr/bin /bin/sh -c ". '$SANDBOX/uwsm-env'; . '$SANDBOX/10-haseen'; printf %s \"\$PATH\"")"
assert_eq "the session PATH starts with haseen's omarchy/bin" "$HASEEN_PATH/omarchy/bin" "${session_path%%:*}"
doctor_fn doctor_omarchy_path compositor "$session_path" "fix it"
assert_status "and passes the doctor" 0 "$STATUS"

# Existing installs get the line through a migration, once.
MIG=1792531693-omarchy-path.sh
FRAG="$XDG_CONFIG_HOME/uwsm/env.d/10-haseen"
run_mig() { capture env HASEEN_PATH="$HASEEN_PATH" HASEEN_MIGRATION="$MIG" bash -Eeuo pipefail "$HASEEN_PATH/migrations/$MIG"; }
run_mig
assert_status "without the fragment the migration has nothing to do" 0 "$STATUS"
assert_eq "and writes nothing" "" "$(ls -A "$XDG_CONFIG_HOME/uwsm" 2>/dev/null)"
mkdir -p "$(dirname "$FRAG")"
printf 'export HASEEN_PATH=/mine\n' >"$FRAG"
run_mig
assert_status "a fragment without the layer's marker is not an error" 0 "$STATUS"
assert_eq "it is the user's and left alone" "export HASEEN_PATH=/mine" "$(<"$FRAG")"
assert_contains "and the user is told why, and of the doctor" "$OUTPUT" "haseen doctor"
printf '# Written by haseen layers/desktop. Rewritten on every apply.\n#export PATH="$HASEEN_PATH/omarchy/bin:$PATH"\nexport HASEEN_PATH=/old\n' >"$FRAG"
run_mig
assert_status "the migration rewrites an old fragment (a commented-out line does not count)" 0 "$STATUS"
assert_eq "with the layer's own content" "$(<"$SANDBOX/10-haseen")" "$(<"$FRAG")"
touch -d '1 hour ago' "$FRAG"
stamp="$(stat -c %Y "$FRAG")"
run_mig
assert_eq "a second run leaves it alone" "$stamp" "$(stat -c %Y "$FRAG")"

# Interactive shells: haseen's shell init puts haseen's commands first after
# whatever the rc prepended, once.
BARE="$SANDBOX/bare-bin"
mkdir -p "$BARE"
for c in bash sh env dirname pwd basename grep sed awk sort tr cat ls; do
    ln -s "$(PATH=/usr/bin:/bin command -v "$c")" "$BARE/$c" 2>/dev/null || true
done
init_path() {
    capture env -i HOME="$HOME" PATH="$1" bash --noprofile --norc -c \
        ". '$HASEEN_PATH/default/shell/init.sh'; printf %s \"\$PATH\""
}
ours="$(readlink -f "$HASEEN_PATH/omarchy/bin")"
init_path "$ROOT/usr/share/omarchy/bin:$BARE"
assert_eq "shell init puts haseen's omarchy/bin first" "$ours:$ROOT/usr/share/omarchy/bin:$BARE" "$OUTPUT"
init_path "$ours:$BARE"
assert_eq "and adds it only once" "$ours:$BARE" "$OUTPUT"
init_path "$ROOT/usr/share/omarchy/bin:$ours:$BARE"
assert_eq "sourced again after another prepend, it moves back to the front, not twice" \
    "$ours:$ROOT/usr/share/omarchy/bin:$BARE" "$OUTPUT"
