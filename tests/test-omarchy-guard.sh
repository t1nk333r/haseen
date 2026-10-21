# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Plan 101: Omarchy's own packages cannot undo haseen. Its migrations are
# recorded as done in Omarchy's ledger (haseen migrate omarchy, the haseen
# migration, the base layer's pacman hook through haseen omarchy guard), its
# login notice is silenced, omarchy-settings' Theme=omarchy is reverted over
# haseen's splash, and haseen doctor says what is left.

# make_root NAME — an Omarchy 4.5 machine: three of its migrations (each would
# record that it ran), both packages, a user with haseen state (alice), one
# without (bob), a system account and a nologin account; sets ROOT.
make_root() {
    ROOT="$SANDBOX/$1"
    local m
    mkdir -p "$ROOT/usr/share/omarchy/migrations" "$ROOT/etc/plymouth" "$ROOT/usr/bin" \
        "$ROOT/var/lib/pacman/local/omarchy-4.5.0-1" "$ROOT/var/lib/pacman/local/omarchy-settings-4.5.0-1" \
        "$ROOT/users/alice/.local/state/haseen" "$ROOT/users/bob/.local/state"
    for m in 1788129995 1790528634 1791898365; do
        printf 'echo "%s ran" >>"$HOME/omarchy-migrations-ran"\n' "$m" >"$ROOT/usr/share/omarchy/migrations/$m.sh"
    done
    cat >"$ROOT/etc/passwd" <<'EOF'
root:x:0:0::/root:/usr/bin/bash
alice:x:1000:1000::/users/alice:/usr/bin/bash
bob:x:1001:1001::/users/bob:/usr/bin/zsh
svc:x:977:977::/var/lib/svc:/usr/bin/bash
nobody:x:65534:65534:Kernel Overflow User:/:/usr/bin/nologin
ghost:x:1002:1002::/users/alice:/usr/bin/nologin
EOF
}

# omarchy_would_run [LEDGER] — what Omarchy's runner would run: its rule
# (bin/omarchy-migrate@v4.5.0-rc1:35-56), a script without a regular file of
# its name in the ledger.
omarchy_would_run() {
    local ledger="${1:-$HOME/.local/state/omarchy/migrations}" f
    for f in "$ROOT/usr/share/omarchy/migrations"/*.sh; do
        [[ -f $ledger/${f##*/} ]] || printf '%s\n' "${f##*/}"
    done
}

# userns — the kernel lets this user map itself to root in a user namespace,
# where files it owns are owned by root (CI's container may not).
userns() { unshare --map-root-user true 2>/dev/null; }

# plant_tree ROOT — this tree's router and guard at their own paths inside
# ROOT, with nothing in ROOT writable by group or others: what an installed
# tree looks like once a user namespace maps this user to root.
plant_tree() {
    mkdir -p "$1$REPO/bin"
    cp "$REPO/bin/haseen" "$REPO/bin/haseen-omarchy-guard" "$1$REPO/bin/"
    chmod -R go-w "$1"
}

# --- haseen migrate omarchy -------------------------------------------------------
sandbox omarchy-guard-seal
make_root seal
export HASEEN_SYSROOT="$ROOT"
ledger="$HOME/.local/state/omarchy/migrations"
# The owner's plugins, one of them the link migration 1790528634 deletes.
mkdir -p "$HOME/.config/omarchy/plugins/me.widget"
printf '{}\n' >"$HOME/.config/omarchy/plugins/me.widget/manifest.json"
ln -s /usr/share/omarchy/shell/plugins/elsewhen "$HOME/.config/omarchy/plugins/omacom.elsewhen"
plugins_sum() { find "$HOME/.config/omarchy/plugins" -printf '%p %y %l\n' | LC_ALL=C sort | sha256sum; }
plugins_before="$(plugins_sum)"
# A migration Omarchy itself ran keeps its own empty marker.
mkdir -p "$ledger"
: >"$ledger/1788129995.sh"

capture haseen migrate omarchy --pending
assert_status "two of Omarchy's migrations are pending for this user" 0 "$STATUS"
assert_eq "pending lists them in the runner's order" $'1790528634.sh\n1791898365.sh' "$OUTPUT"

capture haseen migrate omarchy --dry-run
assert_status "a dry run succeeds" 0 "$STATUS"
assert_dry_pure "seal" "$OUTPUT"
assert_contains "it plans the Limine migration's marker" "$OUTPUT" "DRYRUN: write $ledger/1791898365.sh:"
assert_not_contains "and not the one Omarchy ran" "$OUTPUT" "$ledger/1788129995.sh"
assert_eq "a dry run writes no marker" "1788129995.sh" "$(ls "$ledger")"

capture haseen migrate omarchy
assert_status "the seal succeeds" 0 "$STATUS"
assert_contains "it says how many it sealed" "$OUTPUT" "sealed 2"
assert_eq "Omarchy's runner has nothing left to run" "" "$(omarchy_would_run)"
assert_contains "haseen's markers say who wrote them" "$(cat "$ledger/1791898365.sh")" "sealed by haseen"
assert_eq "Omarchy's own marker is untouched" "0" "$(stat -c %s "$ledger/1788129995.sh")"
assert_eq "no migration ran" "absent" "$([[ -e $HOME/omarchy-migrations-ran ]] && echo present || echo absent)"
assert_eq "the owner's Omarchy plugins are untouched" "$plugins_before" "$(plugins_sum)"
capture haseen migrate omarchy --pending
assert_status "afterwards nothing is pending" 1 "$STATUS"
markers="$(stat -c '%n %Y %s' "$ledger"/* | sha256sum)"
capture haseen migrate omarchy
assert_contains "a second run has nothing to seal" "$OUTPUT" "nothing to seal (3 recorded)"
assert_eq "and rewrites no marker" "$markers" "$(stat -c '%n %Y %s' "$ledger"/* | sha256sum)"

# 4.5 arrives: its new migrations are pending again until sealed.
printf 'true\n' >"$ROOT/usr/share/omarchy/migrations/1791968925.sh"
capture haseen migrate omarchy --pending
assert_eq "a migration the next package adds is pending" "1791968925.sh" "$OUTPUT"

# OMARCHY_MIGRATION_STATE moves Omarchy's ledger; the seal follows it.
capture env OMARCHY_MIGRATION_STATE="$SANDBOX/elsewhere" haseen migrate omarchy
assert_eq "an OMARCHY_MIGRATION_STATE ledger is sealed" "" "$(omarchy_would_run "$SANDBOX/elsewhere")"

# A marker path that is not a file would still let Omarchy run it: that one
# fails, every other is still sealed, and all that failed are named.
printf 'true\n' >"$ROOT/usr/share/omarchy/migrations/1791968926.sh"
printf 'true\n' >"$ROOT/usr/share/omarchy/migrations/1791968927.sh"
mkdir "$ledger/1791968925.sh"
ln -s /nonexistent "$ledger/1791968927.sh"
capture haseen migrate omarchy
assert_status "a directory in a marker's place fails the seal" 1 "$STATUS"
assert_contains "and names the path" "$OUTPUT" "$ledger/1791968925.sh exists but is not a regular file"
assert_contains "a dangling link is named too" "$OUTPUT" "$ledger/1791968927.sh exists but is not a regular file"
assert_contains "the summary lists both" "$OUTPUT" "2 not sealed, so /usr/bin/omarchy-migrate would still run them: 1791968925.sh 1791968927.sh"
assert_eq "the migration between them is still sealed" $'1791968925.sh\n1791968927.sh' "$(omarchy_would_run)"
assert_contains "and counted" "$OUTPUT" "sealed 1"
rmdir "$ledger/1791968925.sh"
rm "$ledger/1791968927.sh"
capture haseen migrate omarchy
assert_status "once they are cleared the seal completes" 0 "$STATUS"
assert_eq "nothing is left" "" "$(omarchy_would_run)"

capture haseen migrate omarchy --bogus
assert_status "an unknown argument is a usage error" 2 "$STATUS"
capture env HASEEN_SYSROOT="$SANDBOX/no-omarchy" haseen migrate omarchy
assert_status "without Omarchy's package there is nothing to do" 0 "$STATUS"
assert_contains "and it says so" "$OUTPUT" "nothing to seal"

# --- the haseen migration ----------------------------------------------------------
sandbox omarchy-guard-migration
make_root migration
export HASEEN_SYSROOT="$ROOT"
migration="$(cd "$REPO/share/haseen/migrations" && ls ./*-seal-omarchy-migrations.sh)"
migration="${migration#./}"
mkdir -p "$SANDBOX/migrations"
cp "$REPO/share/haseen/migrations/$migration" "$SANDBOX/migrations/"
export HASEEN_MIGRATIONS_DIR="$SANDBOX/migrations"
capture haseen migrate
assert_status "the haseen migration runs" 0 "$STATUS"
assert_eq "it seals every Omarchy migration for this user" "" "$(omarchy_would_run)"
assert_eq "it is recorded in haseen's ledger" "applied" "$(cut -d' ' -f1 "$XDG_STATE_HOME/haseen/migrations/$migration")"
export HASEEN_SYSROOT="$SANDBOX/no-omarchy"
capture env HASEEN_MIGRATION="$migration" bash -Eeuo pipefail "$SANDBOX/migrations/$migration"
assert_status "without Omarchy's package the migration is a no-op" 0 "$STATUS"
unset HASEEN_MIGRATIONS_DIR

# --- haseen omarchy guard (the pacman hook's command) -----------------------------
sandbox omarchy-guard-hook
make_root guard
export HASEEN_SYSROOT="$ROOT"
printf '#!/bin/sh\nexit 0\n' >"$ROOT/usr/bin/plymouth-set-default-theme"
chmod +x "$ROOT/usr/bin/plymouth-set-default-theme"
mkdir -p "$ROOT/usr/share/plymouth/themes/haseen"
: >"$ROOT/usr/share/plymouth/themes/haseen/haseen.plymouth"
printf '[Daemon]\nTheme=omarchy\n' >"$ROOT/etc/plymouth/plymouthd.conf"

capture haseen omarchy guard
assert_status "not as root, and not a dry run: refused" 1 "$STATUS"
assert_contains "it says how to run it" "$OUTPUT" "sudo haseen omarchy guard"
# As pacman runs it, every path exits 0, and what failed is still said.
capture haseen omarchy guard --hook
assert_status "under --hook even that refusal exits 0" 0 "$STATUS"
assert_contains "and is reported" "$OUTPUT" "run it as root"
capture haseen omarchy guard --hook --bogus
assert_status "under --hook a bad argument exits 0" 0 "$STATUS"
assert_contains "after the usage" "$OUTPUT" "Usage: sudo haseen omarchy guard"
capture haseen omarchy guard --bogus
assert_status "without --hook it is a usage error" 2 "$STATUS"

capture haseen omarchy guard --dry-run
assert_status "a dry run plans as any user" 0 "$STATUS"
assert_dry_pure "guard" "$OUTPUT"
assert_contains "it seals for the user with haseen state, as that user" "$OUTPUT" \
    "DRYRUN: sudo runuser -u alice -- env -i HOME=$ROOT/users/alice USER=alice LOGNAME=alice"
assert_contains "through haseen's seal command" "$OUTPUT" "haseen-migrate-omarchy --dry-run"
assert_not_contains "not for a user haseen never ran for" "$OUTPUT" "runuser -u bob"
assert_not_contains "nor for system or nologin accounts" "$(grep -E 'runuser -u (svc|nobody|ghost|root) ' <<<"$OUTPUT" || true)" "runuser"
assert_contains "Theme=omarchy over haseen's installed splash is reverted" "$OUTPUT" \
    "DRYRUN: sudo plymouth-set-default-theme haseen"
for theme in haseen spinner; do
    printf '[Daemon]\nTheme=%s\n' "$theme" >"$ROOT/etc/plymouth/plymouthd.conf"
    capture haseen omarchy guard --dry-run
    assert_not_contains "Theme=$theme is left as it is" "$OUTPUT" "plymouth-set-default-theme"
done
printf '[Daemon]\nTheme=omarchy\n' >"$ROOT/etc/plymouth/plymouthd.conf"
rm "$ROOT/usr/share/plymouth/themes/haseen/haseen.plymouth"
capture haseen omarchy guard --dry-run
assert_not_contains "without haseen's splash installed, Omarchy's stays" "$OUTPUT" "plymouth-set-default-theme"
: >"$ROOT/usr/share/plymouth/themes/haseen/haseen.plymouth"
capture haseen plymouth status
assert_contains "plymouth status says who put Omarchy's splash back" "$OUTPUT" \
    "theme:     omarchy (Omarchy's omarchy-settings package put it back over haseen's: sudo haseen omarchy guard)"

# As root, through user namespaces where the kernel allows them: root maps to
# this user, and the runuser stand-in drops to an unprivileged id the same
# way, so the seal itself runs as a non-root user, as it does under pacman.
if userns && unshare --map-root-user unshare --map-user=1000 --map-group=1000 true 2>/dev/null; then
    stub runuser 'while [ "$1" != "--" ]; do shift; done; shift
echo "runuser: $*" >>"$GUARD_LOG"
exec unshare --map-user=1000 --map-group=1000 -- "$@"'
    stub plymouth-set-default-theme 'echo "plymouth-set-default-theme $*" >>"$GUARD_LOG"; printf "[Daemon]\nTheme=%s\n" "$1" >"$HASEEN_SYSROOT/etc/plymouth/plymouthd.conf"'
    export GUARD_LOG="$SANDBOX/guard.log"
    capture unshare --map-root-user "$REPO/bin/haseen" omarchy guard --hook
    assert_status "as root the hook's run succeeds" 0 "$STATUS"
    assert_eq "alice's Omarchy ledger is sealed" "" "$(omarchy_would_run "$ROOT/users/alice/.local/state/omarchy/migrations")"
    assert_eq "bob's is not written" "absent" "$([[ -e $ROOT/users/bob/.local/state/omarchy ]] && echo present || echo absent)"
    assert_contains "the seal ran with a clean environment" "$(cat "$GUARD_LOG")" "env -i HOME=$ROOT/users/alice USER=alice"
    assert_contains "haseen's splash is named again" "$(cat "$ROOT/etc/plymouth/plymouthd.conf")" "Theme=haseen"
    assert_eq "no Omarchy migration ran" "absent" "$([[ -e $ROOT/users/alice/omarchy-migrations-ran ]] && echo present || echo absent)"
    # As root the guard runs its own tree's code, whatever HASEEN_PATH says.
    mkdir -p "$SANDBOX/elsewhere/lib"
    printf 'touch "%s/elsewhere-ran"\n' "$SANDBOX" >"$SANDBOX/elsewhere/lib/omarchy-guard.sh"
    capture env HASEEN_PATH="$SANDBOX/elsewhere" unshare --map-root-user "$REPO/bin/haseen" omarchy guard
    assert_status "an inherited HASEEN_PATH does not stop it" 0 "$STATUS"
    assert_eq "and none of its code ran as root" "absent" "$([[ -e $SANDBOX/elsewhere-ran ]] && echo present || echo absent)"
    # A seal that fails: --hook reports it and still exits 0 (a pacman hook's
    # failure aborts nothing PostTransaction, and the splash step still runs);
    # without --hook the command fails.
    printf 'true\n' >"$ROOT/usr/share/omarchy/migrations/1791968925.sh"
    mkdir -p "$ROOT/users/alice/.local/state/omarchy/migrations/1791968925.sh"
    printf '[Daemon]\nTheme=omarchy\n' >"$ROOT/etc/plymouth/plymouthd.conf"
    capture unshare --map-root-user "$REPO/bin/haseen" omarchy guard --hook
    assert_status "a failed seal under --hook still exits 0" 0 "$STATUS"
    assert_contains "and is reported" "$OUTPUT" "Omarchy's migrations were not sealed for alice"
    assert_contains "the splash step still ran" "$(cat "$ROOT/etc/plymouth/plymouthd.conf")" "Theme=haseen"
    capture unshare --map-root-user "$REPO/bin/haseen" omarchy guard
    assert_status "without --hook the failure is the exit status" 1 "$STATUS"
else
    echo "  SKIP root-mode guard checks: user namespaces are not available here" >&2
fi

# --- the pacman hook and the base layer ---------------------------------------------
sandbox omarchy-guard-layer
hook="$(HASEEN_PATH="$REPO/share/haseen" bash -c 'source "$HASEEN_PATH/lib/omarchy-guard.sh"; omarchy_guard_hook_render /usr/local/bin/haseen')"
assert_contains "the hook runs the guard from the haseen it was installed from" "$hook" \
    "Exec = /usr/local/bin/haseen omarchy guard --hook"
assert_eq "it fires on omarchy and omarchy-settings, install and upgrade, after the transaction" \
    $'Install\nUpgrade\nomarchy\nomarchy-settings\nPostTransaction' \
    "$(sed -n 's/^\(Operation\|Target\|When\) = //p' <<<"$hook")"
assert_eq "it sorts before the Limine and initramfs hooks" \
    "50-haseen-omarchy.hook 80-limine-efi-deploy.hook 90-mkinitcpio-install.hook" \
    "$(printf '%s\n' 90-mkinitcpio-install.hook 50-haseen-omarchy.hook 80-limine-efi-deploy.hook | LC_ALL=C sort | paste -sd' ')"

# The hook runs its Exec as root: it is written only for a haseen that only
# root can change, along its whole path (root_trusted_exec).
capture env HASEEN_SYSROOT= bash -c 'source "$HASEEN_PATH/lib/common.sh"; root_trusted_exec "$1"' _ "$REPO/bin/haseen"
assert_status "a haseen in this user's checkout cannot be trusted with root" 1 "$STATUS"
assert_contains "the reason names the owner" "$OUTPUT" "is owned by uid $(id -u), not root"
fx="$SANDBOX/root"
cp -a "$FIXTURES/desk-cachyos-amd" "$fx"
capture env HASEEN_SYSROOT="$fx" haseen layer apply base --dry-run
assert_status "base layer dry run" 0 "$STATUS"
assert_dry_pure "base with the guard" "$OUTPUT"
assert_not_contains "from a tree root does not own, the hook is not written" "$OUTPUT" "50-haseen-omarchy.hook (mode"
assert_contains "and the layer says why and what to do" "$OUTPUT" \
    "Omarchy package guard: pacman hook not written: the hook's $REPO/bin/haseen runs as root, but / is owned by uid $(id -u), not root; install haseen as root (./install.sh)"
base_guard() { capture env DRY_RUN=true HASEEN_SYSROOT="$fx" unshare --map-root-user bash -c 'source "$HASEEN_PATH/lib/layers.sh"; _layer_env base; base_omarchy_guard'; }
if userns; then
    plant_tree "$fx"
    base_guard
    assert_status "the guard step from a root-owned tree" 0 "$STATUS"
    assert_contains "writes the hook" "$OUTPUT" "DRYRUN: write /etc/pacman.d/hooks/50-haseen-omarchy.hook (mode 0644):"
    assert_contains "with that tree's haseen" "$OUTPUT" "    | Exec = $REPO/bin/haseen omarchy guard --hook"
    chmod g+w "$fx$(dirname "$REPO")"
    base_guard
    assert_not_contains "an ancestor its group can write: not written" "$OUTPUT" "50-haseen-omarchy.hook (mode"
    assert_contains "and named" "$OUTPUT" "but $(dirname "$REPO") is writable by its group or by others"
    chmod g-w "$fx$(dirname "$REPO")"
    # The guard as a link elsewhere: every directory on the link's way counts.
    rm "$fx$REPO/bin/haseen-omarchy-guard"
    mkdir -p "$fx$SANDBOX"
    cp "$REPO/bin/haseen-omarchy-guard" "$fx$SANDBOX/real-guard"
    ln -s "$SANDBOX/real-guard" "$fx$REPO/bin/haseen-omarchy-guard"
    chmod -R go-w "$fx"
    base_guard
    assert_contains "a link to a root-owned file is followed" "$OUTPUT" "DRYRUN: write /etc/pacman.d/hooks/50-haseen-omarchy.hook"
    chmod o+w "$fx$SANDBOX"
    base_guard
    assert_contains "into a directory others can write: refused" "$OUTPUT" "but $SANDBOX is writable by its group or by others"
    chmod o-w "$fx$SANDBOX"
else
    echo "  SKIP root-owned tree checks: user namespaces are not available here" >&2
fi
capture env HASEEN_SYSROOT="$fx" haseen layer status base
assert_not_contains "without Omarchy's packages a missing hook is no fault" "$OUTPUT" "Omarchy package guard"
mkdir -p "$fx/var/lib/pacman/local/omarchy-settings-4.5.0-1"
capture env HASEEN_SYSROOT="$fx" haseen layer status base
assert_contains "with them it is" "$OUTPUT" "missing: Omarchy package guard /etc/pacman.d/hooks/50-haseen-omarchy.hook (haseen layer apply base)"
mkdir -p "$fx/etc/pacman.d/hooks"
HASEEN_PATH="$REPO/share/haseen" bash -c 'source "$HASEEN_PATH/lib/omarchy-guard.sh"; omarchy_guard_hook_render' \
    >"$fx/etc/pacman.d/hooks/50-haseen-omarchy.hook"
capture env HASEEN_SYSROOT="$fx" haseen layer status base
assert_contains "a hook that runs a tree a user owns is a warning" "$OUTPUT" \
    "warn: Omarchy package guard: the hook's $REPO/bin/haseen runs as root, but / is owned by uid $(id -u)"
if userns; then
    capture env HASEEN_SYSROOT="$fx" unshare --map-root-user bash -c 'source "$HASEEN_PATH/lib/layers.sh"; layer_run_status base'
    assert_contains "an installed hook from a root-owned tree is reported" "$OUTPUT" "ok: Omarchy package guard"
    base_guard
    assert_contains "and not written again" "$OUTPUT" "Omarchy package guard: pacman hook in place"
    assert_not_contains "never twice" "$OUTPUT" "write /etc/pacman.d/hooks/50-haseen-omarchy.hook"
fi

# --- the drop-in for Omarchy's login notice --------------------------------------
dropin="$REPO/share/haseen/default/omarchy-guard/omarchy-migrate-notify.conf"
assert_eq "it replaces the unit's command with a no-op" $'ExecStart=\nExecStart=/usr/bin/true' "$(grep '^ExecStart' "$dropin")"
capture env HASEEN_SYSROOT="$FIXTURES/cachyos-grub-plain" "$REPO/install.sh" --dry-run --tree-only --prefix /usr/local
assert_contains "the tree install puts it beside haseen's user units" "$OUTPUT" \
    "DRYRUN: sudo install -Dm0644 $dropin /usr/local/lib/systemd/user/omarchy-migrate-notify.service.d/haseen.conf"
assert_not_contains "and writes nothing under /etc" "$OUTPUT" "write /etc/"
prefix="$SANDBOX/prefix"
mkdir -p "$prefix/lib/systemd/user/omarchy-migrate-notify.service.d"
cp "$dropin" "$prefix/lib/systemd/user/omarchy-migrate-notify.service.d/haseen.conf"
capture env HASEEN_SYSROOT="$FIXTURES/cachyos-grub-plain" "$REPO/install.sh" --dry-run --uninstall-tree --prefix "$prefix"
assert_contains "uninstalling the tree removes it" "$OUTPUT" \
    "DRYRUN: sudo rm -f $prefix/lib/systemd/user/omarchy-migrate-notify.service.d/haseen.conf"

# --- haseen doctor ---------------------------------------------------------------
sandbox omarchy-guard-doctor
make_root doctor
export HASEEN_SYSROOT="$ROOT"
doctor() { capture bash -c 'source "$HASEEN_PATH/lib/omarchy-guard.sh"; omarchy_guard_doctor'; }
doctor
assert_status "unsealed migrations and no hook fail the check" 1 "$STATUS"
assert_contains "the unsealed count is given" "$OUTPUT" "omarchy migrations=3 of 3 not sealed"
assert_contains "the missing hook is named" "$OUTPUT" "omarchy pacman hook=missing"
haseen migrate omarchy >/dev/null
mkdir -p "$ROOT/etc/pacman.d/hooks"
bash -c 'source "$HASEEN_PATH/lib/omarchy-guard.sh"; omarchy_guard_hook_render' >"$ROOT/etc/pacman.d/hooks/50-haseen-omarchy.hook"
mkdir -p "$XDG_CONFIG_HOME/systemd/user/graphical-session.target.wants" "$ROOT/etc/systemd/user/default.target.wants"
ln -s /usr/lib/systemd/user/owed.service "$XDG_CONFIG_HOME/systemd/user/graphical-session.target.wants/owed.service"
ln -s /usr/lib/systemd/user/omarchy-migrate-notify.service \
    "$XDG_CONFIG_HOME/systemd/user/graphical-session.target.wants/omarchy-migrate-notify.service"
ln -s /usr/lib/systemd/user/haseen-shell.service "$XDG_CONFIG_HOME/systemd/user/graphical-session.target.wants/haseen-shell.service"
ln -s /usr/lib/systemd/user/bt-agent.service "$ROOT/etc/systemd/user/default.target.wants/bt-agent.service"
doctor
assert_status "a hook that runs a tree a user owns fails the check" 1 "$STATUS"
assert_contains "and says why" "$OUTPUT" \
    "omarchy pacman hook=unsafe: the hook's $REPO/bin/haseen runs as root, but / is owned by uid $(id -u), not root"
assert_contains "the seal is reported" "$OUTPUT" "omarchy migrations=sealed (3)"
if userns; then
    plant_tree "$ROOT"
    capture unshare --map-root-user bash -c 'source "$HASEEN_PATH/lib/omarchy-guard.sh"; omarchy_guard_doctor'
    assert_status "sealed and hooked from a root-owned tree: the check passes" 0 "$STATUS"
    assert_contains "and the hook is reported" "$OUTPUT" "omarchy pacman hook=installed (/etc/pacman.d/hooks/50-haseen-omarchy.hook)"
fi
assert_contains "an enabled owed is listed with what to do" "$OUTPUT" \
    "omarchy user unit=owed.service enabled (graphical-session.target): a second wallpaper daemon beside haseen-background.service"
assert_contains "a globally enabled one is listed" "$OUTPUT" "omarchy user unit=bt-agent.service enabled (default.target)"
assert_contains "Omarchy's notice without haseen's drop-in says so" "$OUTPUT" \
    "omarchy user unit=omarchy-migrate-notify.service enabled (graphical-session.target): a second, Omarchy-branded"
assert_not_contains "haseen's own units are not listed" "$OUTPUT" "haseen-shell.service"
mkdir -p "$ROOT$REPO/lib/systemd/user/omarchy-migrate-notify.service.d"
cp "$REPO/share/haseen/default/omarchy-guard/omarchy-migrate-notify.conf" \
    "$ROOT$REPO/lib/systemd/user/omarchy-migrate-notify.service.d/haseen.conf"
doctor
assert_contains "with the drop-in it is reported silenced" "$OUTPUT" \
    "omarchy-migrate-notify.service enabled (graphical-session.target): silenced by haseen's drop-in"
mkdir -p "$ROOT/usr/share/plymouth/themes/haseen"
printf '#!/bin/sh\n' >"$ROOT/usr/bin/plymouth-set-default-theme"
chmod +x "$ROOT/usr/bin/plymouth-set-default-theme"
: >"$ROOT/usr/share/plymouth/themes/haseen/haseen.plymouth"
printf '[Daemon]\nTheme=omarchy\n' >"$ROOT/etc/plymouth/plymouthd.conf"
doctor
assert_status "Omarchy's splash over haseen's fails the check" 1 "$STATUS"
assert_contains "and says how to fix it" "$OUTPUT" "splash=Omarchy's omarchy-settings put Theme=omarchy back: sudo haseen omarchy guard"
capture env HASEEN_SYSROOT="$SANDBOX/no-omarchy" bash -c 'source "$HASEEN_PATH/lib/omarchy-guard.sh"; omarchy_guard_doctor'
assert_status "a machine without Omarchy passes" 0 "$STATUS"
assert_eq "with one line" "omarchy package=not installed (nothing to guard)" "$OUTPUT"

# --- the polkit repair the seal would skip ---------------------------------------
# Omarchy's migration 1788256455, carried as haseen's 1792605417: only the
# exact stack Omarchy's old fingerprint/FIDO2 setup wrote is rewritten.
sandbox omarchy-guard-polkit
polkit_migration="$REPO/share/haseen/migrations/1792605417-polkit-faillock.sh"
proot="$SANDBOX/root"
mkdir -p "$proot/etc/pam.d"
polkit_plan() {
    capture env DRY_RUN=true HASEEN_SYSROOT="$proot" HASEEN_MIGRATION=1792605417-polkit-faillock.sh \
        bash -Eeuo pipefail "$polkit_migration"
}
vulnerable='#%PAM-1.0
auth      [success=1 default=ignore] pam_exec.so quiet /usr/bin/omarchy-hw-laptop-closed
auth      sufficient pam_fprintd.so
auth      sufficient pam_u2f.so cue authfile=/etc/fido2/fido2
auth      required pam_unix.so
account   required pam_unix.so
password  required pam_unix.so
session   required pam_unix.so'
printf '%s\n' "$vulnerable" >"$proot/etc/pam.d/polkit-1"
polkit_plan
assert_status "the vulnerable stack is planned for repair" 0 "$STATUS"
assert_dry_pure "polkit repair" "$OUTPUT"
assert_contains "with a backup first" "$OUTPUT" "DRYRUN: sudo cp -a /etc/pam.d/polkit-1 /etc/pam.d/polkit-1.haseen-bak."
assert_contains "then the in-place rewrite" "$OUTPUT" "DRYRUN: sudo sed -i -E"
expr="$(sed -n "s/^if ! run_root sed -i -E '\(.*\)' \"\$POLKIT_PAM\"; then\$/\1/p" "$polkit_migration")"
printf '%s\n' "$vulnerable" >"$SANDBOX/polkit-1"
sed -i -E "$expr" "$SANDBOX/polkit-1"
assert_eq "the rewrite turns each bare pam_unix line into an include of system-auth" \
    $'auth      include system-auth\naccount   include system-auth\npassword  include system-auth\nsession   include system-auth' \
    "$(grep 'system-auth' "$SANDBOX/polkit-1")"
assert_eq "and keeps the hardware lines and comments" "4" "$(grep -c -e '^#' -e pam_fprintd -e pam_u2f -e pam_exec "$SANDBOX/polkit-1")"
for case in fixed edited missing; do
    case "$case" in
    fixed) printf '%s\n' "$vulnerable" | sed -E "$expr" >"$proot/etc/pam.d/polkit-1" ;;
    edited) printf '%s\nauth      required pam_deny.so\n' "$vulnerable" >"$proot/etc/pam.d/polkit-1" ;;
    missing) rm -f "$proot/etc/pam.d/polkit-1" ;;
    esac
    polkit_plan
    assert_status "a $case polkit-1 is fine" 0 "$STATUS"
    assert_not_contains "and is left alone" "$OUTPUT" "sudo"
done
