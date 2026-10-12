# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Consumer-visible archive policy boundaries; no hook/helper is executed.
source "$FIXTURES/vapt-lib.sh"
followup_case() {
    vapt_sandbox "$1"
    vapt_root
    vapt_package subject 2-1
    PACKAGE="$SANDBOX/packages/subject"
    ARCHIVE="$SANDBOX/archives/subject-2-1-x86_64.pkg.tar.gz"
}
repack() {
    local members=(.PKGINFO usr)
    [[ ! -f $PACKAGE/.INSTALL ]] || members+=(.INSTALL)
    [[ ! -d $PACKAGE/etc ]] || members+=(etc)
    tar -czf "$ARCHIVE" -C "$PACKAGE" "${members[@]}"
}
review() { capture python3 "$VAPT_META" audit "$ARCHIVE" --root "$ROOT"; }
activation_hook() { # FILE OPERATION TYPE TARGET WHEN EXEC
    mkdir -p "${1%/*}"
    printf '[Trigger]\nOperation = %s\nType = %s\nTarget = %s\n[Action]\nWhen = %s\nExec = %s\n' \
        "$2" "$3" "$4" "$5" "$6" >"$1"
}

# Ordinary service definitions and aliases do not enable a unit. Dependency
# links do, even without an activation scriptlet or systemctl invocation.
for directory in etc/systemd/system usr/lib/systemd/system; do
    for relation in wants requires; do
        followup_case "vapt-enabled-${directory//\//-}-$relation"
        mkdir -p "$PACKAGE/$directory" "$PACKAGE/usr/lib/systemd/system"
        printf '[Service]\nExecStart=/usr/bin/subject\n' >"$PACKAGE/usr/lib/systemd/system/subject.service"
        ln -s /usr/lib/systemd/system/subject.service "$PACKAGE/$directory/alias.service"
        repack
        review
        assert_status "$directory ordinary unit/alias remains provisionable" 0 "$STATUS"
        mkdir -p "$PACKAGE/$directory/multi-user.target.$relation"
        ln -s /usr/lib/systemd/system/subject.service "$PACKAGE/$directory/multi-user.target.$relation/subject.service"
        repack
        review
        assert_status "$directory .$relation unit enables service and is refused" 1 "$STATUS"
        vapt_tools_untouched "$directory $relation"
    done
done

# Pre phases run CURRENT helper bytes; post phases run reviewed replacement
# bytes. Both inverse vectors prevent an implementation rejecting everything.
for phase in pre_install pre_upgrade post_install post_upgrade; do
    followup_case "vapt-helper-time-$phase"
    if [[ $phase == *_upgrade ]]; then
        vapt_installed 'subject|1-1|https://example.org/||||usr/bin/subject,usr/lib/subject/setup'
    fi
    # Scriptlets run through the base-proven /bin/sh: stock owners, no hooks.
    vapt_stock
    rm -f "$ROOT"/usr/share/libalpm/hooks/*.hook
    mkdir -p "$PACKAGE/usr/lib/subject" "$ROOT/usr/lib/subject"
    printf '%s() {\n /usr/lib/subject/setup\n}\n' "$phase" >"$PACKAGE/.INSTALL"
    for current in activating inert; do
        if [[ $current == activating ]]; then
            printf '#!/bin/sh\nsystemctl start subject.socket\n' >"$ROOT/usr/lib/subject/setup"
            printf '#!/bin/sh\nexit 0\n' >"$PACKAGE/usr/lib/subject/setup"
        else
            printf '#!/bin/sh\nexit 0\n' >"$ROOT/usr/lib/subject/setup"
            printf '#!/bin/sh\nsystemctl start subject.socket\n' >"$PACKAGE/usr/lib/subject/setup"
        fi
        repack
        review
        expected=0
        if [[ $phase == pre_* && $current == activating || $phase == post_* && $current == inert ]]; then expected=1; fi
        assert_status "$phase observes $current current bytes, not the wrong temporal view" "$expected" "$STATUS"
    done
    vapt_tools_untouched "$phase helper audit"
done

followup_case vapt-pretransaction-hook-replacement
vapt_installed 'subject|1-1|https://example.org/||||usr/bin/subject,usr/lib/subject/setup,usr/share/libalpm/hooks/setup.hook'
mkdir -p "$PACKAGE/usr/lib/subject" "$ROOT/usr/lib/subject"
printf '#!/bin/sh\nsystemctl start subject.socket\n' >"$ROOT/usr/lib/subject/setup"
printf '#!/bin/sh\nexit 0\n' >"$PACKAGE/usr/lib/subject/setup"
activation_hook "$ROOT/usr/share/libalpm/hooks/setup.hook" Upgrade Package subject PreTransaction /usr/lib/subject/setup
# An incoming inert same-name hook cannot mask the existing pre hook.
activation_hook "$PACKAGE/usr/share/libalpm/hooks/setup.hook" Upgrade Package subject PostTransaction /usr/lib/subject/setup
repack
review
assert_status 'current pre hook/helper cannot be hidden by future inert replacements' 1 "$STATUS"
printf '#!/bin/sh\nexit 0\n' >"$ROOT/usr/lib/subject/setup"
review
assert_status 'current inert pre hook and future inert replacement accepted' 0 "$STATUS"
vapt_tools_untouched 'temporal hook replacement'

# /etc is a fallback, not an unconditional priority layer. Explicit HookDir
# directives are repeatable lists; the final directory wins a basename mask.
for variant in default explicit whitespace repeated late-mask early-mask; do
    followup_case "vapt-hookdirs-$variant"
    activation_hook "$ROOT/usr/share/libalpm/hooks/activate.hook" Install Package subject PostTransaction '/usr/bin/systemctl start subject.socket'
    mkdir -p "$ROOT/etc/pacman.d/hooks" "$ROOT/opt/early-hooks" "$ROOT/opt/late-hooks"
    ln -s /dev/null "$ROOT/etc/pacman.d/hooks/activate.hook"
    case "$variant" in
    default) ;;
    explicit) vapt_conf_add $'[options]\nHookDir = /opt/early-hooks' ;;
    whitespace) vapt_conf_add $'[options]\nHookDir = /opt/early-hooks   /opt/late-hooks'
        activation_hook "$ROOT/opt/late-hooks/activate.hook" Install Package subject PostTransaction '/usr/bin/systemctl start subject.socket' ;;
    repeated) vapt_conf_add $'[options]\nHookDir = /opt/early-hooks\nHookDir = /opt/late-hooks'
        activation_hook "$ROOT/opt/late-hooks/activate.hook" Install Package subject PostTransaction '/usr/bin/systemctl start subject.socket' ;;
    late-mask) vapt_conf_add $'[options]\nHookDir = /opt/early-hooks /opt/late-hooks'
        activation_hook "$ROOT/opt/early-hooks/activate.hook" Install Package subject PostTransaction '/usr/bin/systemctl start subject.socket'
        ln -s /dev/null "$ROOT/opt/late-hooks/activate.hook" ;;
    early-mask) vapt_conf_add $'[options]\nHookDir = /opt/early-hooks\nHookDir = /opt/late-hooks'
        ln -s /dev/null "$ROOT/opt/early-hooks/activate.hook"
        activation_hook "$ROOT/opt/late-hooks/activate.hook" Install Package subject PostTransaction '/usr/bin/systemctl start subject.socket' ;;
    esac
    review
    expected=1
    [[ $variant != default && $variant != late-mask ]] || expected=0
    assert_status "$variant HookDir effective search and mask precedence" "$expected" "$STATUS"
    vapt_tools_untouched "HookDir $variant"
done

# libalpm path operations are per-file, not package-level Upgrade. The same
# upgrade must trigger only Remove(old), Install(new), Upgrade(shared).
for path in old new shared; do
    for operation in Install Upgrade Remove; do
        followup_case "vapt-path-$path-$operation"
        vapt_installed 'subject|1-1|https://example.org/||||usr/bin/subject,usr/lib/subject/old,usr/lib/subject/shared'
        mkdir -p "$PACKAGE/usr/lib/subject"
        printf 'new data\n' >"$PACKAGE/usr/lib/subject/new"
        printf 'shared data\n' >"$PACKAGE/usr/lib/subject/shared"
        activation_hook "$ROOT/usr/share/libalpm/hooks/path.hook" "$operation" Path "usr/lib/subject/$path" PostTransaction '/usr/bin/systemctl start subject.socket'
        repack
        review
        expected=0
        if [[ $path == old && $operation == Remove || $path == new && $operation == Install || $path == shared && $operation == Upgrade ]]; then expected=1; fi
        assert_status "$path file has $operation trigger relevance during package upgrade" "$expected" "$STATUS"
    done
done
followup_case vapt-path-unknown-old-files
vapt_installed 'subject|1-1|https://example.org/||||?'
activation_hook "$ROOT/usr/share/libalpm/hooks/path.hook" Remove Path 'usr/lib/subject/old' PostTransaction '/usr/bin/systemctl start subject.socket'
review
assert_status 'missing old file inventory cannot prove a removal hook irrelevant' 1 "$STATUS"
vapt_tools_untouched 'unknown old files'
