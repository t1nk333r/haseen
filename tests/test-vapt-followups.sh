# shellcheck shell=bash
# haseen:covers share/haseen/layers/vapt/** tests/fixtures/vapt-host/**
# haseen:covers tests/fixtures/vapt-driver.py tests/fixtures/vapt-lib.sh
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
    [[ ! -d $PACKAGE/opt ]] || members+=(opt)
    [[ ! -e $PACKAGE/run ]] || members+=(run)
    [[ ! -e $PACKAGE/lib ]] || members+=(lib)
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
# systemd.unit(5) also enables through .upholds/ and reads user units from
# /etc/xdg/systemd/user, the default $XDG_CONFIG_DIRS (plan 195).
for directory in etc/systemd/system usr/lib/systemd/system etc/xdg/systemd/user usr/lib/systemd/user; do
    for relation in wants requires upholds; do
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

# A unit drop-in that adds a starting dependency enables the unit just as a
# link does; other drop-ins (environment, limits) stay provisionable. A
# symlinked drop-in cannot be read here and needs manual review (plan 195).
for dropin in wants requires bindsto upholds environment symlink; do
    followup_case "vapt-enabled-dropin-$dropin"
    mkdir -p "$PACKAGE/usr/lib/systemd/system/multi-user.target.d"
    printf '[Service]\nExecStart=/usr/bin/subject\n' >"$PACKAGE/usr/lib/systemd/system/subject.service"
    expected=1
    case "$dropin" in
    wants) body='[Unit]\nWants=subject.service\n' ;;
    requires) body='[Unit]\n  Requires = subject.service\n' ;;
    bindsto) body='[Unit]\nBindsTo=subject.service\n' ;;
    upholds) body='[Unit]\nUpholds=subject.service\n' ;;
    environment) body='[Service]\nEnvironment=SUBJECT_WANTS=1\n'; expected=0 ;;
    symlink) body='' ;;
    esac
    if [[ $dropin == symlink ]]; then
        ln -s /etc/subject/override.conf "$PACKAGE/usr/lib/systemd/system/multi-user.target.d/subject.conf"
    else
        printf '%b' "$body" >"$PACKAGE/usr/lib/systemd/system/multi-user.target.d/subject.conf"
    fi
    repack
    review
    assert_status "multi-user.target.d drop-in ($dropin) is $( ((expected)) && echo refused || echo provisionable)" "$expected" "$STATUS"
    vapt_tools_untouched "drop-in $dropin"
done

# A link that stands in for a directory systemd reads hides that directory's
# members from the archive listing: a symlinked multi-user.target.d whose
# target holds Wants=subject.service enables subject as surely as a .wants
# link. Every link under a systemd root not named like a unit is refused;
# a unit alias stays provisionable (the loop above).
for link in usr/lib/systemd/system/multi-user.target.d usr/lib/systemd/user/default.target.d \
    etc/systemd/system.control usr/local/lib/systemd/system usr/lib/systemd/system/subject.conf; do
    followup_case "vapt-enabled-dirlink-${link//\//-}"
    mkdir -p "$PACKAGE/opt/subject/dropins" "$PACKAGE/${link%/*}" "$PACKAGE/usr/lib/systemd/system"
    printf '[Service]\nExecStart=/usr/bin/subject\n' >"$PACKAGE/usr/lib/systemd/system/subject.service"
    printf '[Unit]\nWants=subject.service\n' >"$PACKAGE/opt/subject/dropins/subject.conf"
    repack
    review
    assert_status "$link without the link is provisionable" 0 "$STATUS"
    ln -s /opt/subject/dropins "$PACKAGE/$link"
    repack
    review
    assert_status "$link as a link is refused" 1 "$STATUS"
    assert_contains "$link refusal names the link" "$OUTPUT" "may hide a unit or drop-in directory $link"
    vapt_tools_untouched "directory link $link"
done

# The rule above sees only names below a systemd root. A link AT a root or
# above one swaps in the whole tree systemd reads there: usr/local/lib/systemd
# belongs to no package, so pacman creates the link and systemd reads
# /usr/local/lib/systemd/system/multi-user.target.d/subject.conf at boot.
for link in usr/local/lib/systemd etc/xdg/systemd usr/share/systemd run/systemd lib/systemd \
    usr/local/lib etc/xdg; do
    followup_case "vapt-enabled-rootlink-${link//\//-}"
    tree=$PACKAGE/opt/subject/dropins
    [[ $link == */systemd ]] || tree+=/systemd
    mkdir -p "$tree/system/multi-user.target.d" "$tree/user/default.target.d" "$PACKAGE/${link%/*}" \
        "$PACKAGE/usr/lib/systemd/system"
    printf '[Service]\nExecStart=/usr/bin/subject\n' >"$PACKAGE/usr/lib/systemd/system/subject.service"
    printf '[Unit]\nWants=subject.service\n' >"$tree/system/multi-user.target.d/subject.conf"
    printf '[Unit]\nWants=subject.service\n' >"$tree/user/default.target.d/subject.conf"
    repack
    review
    assert_status "$link without the link is provisionable" 0 "$STATUS"
    ln -s /opt/subject/dropins "$PACKAGE/$link"
    repack
    review
    assert_status "$link as a link is refused" 1 "$STATUS"
    assert_contains "$link refusal names the link" "$OUTPUT" "replaces a systemd unit directory $link"
    vapt_tools_untouched "root link $link"
done
# A link that only maps one systemd root onto another changes nothing systemd
# reads: filesystem's lib -> usr/lib, which the private -Syuw brings in when
# filesystem updates, stays provisionable in both spellings. Pointing it
# anywhere else is refused.
for target in usr/lib /usr/lib opt/subject; do
    followup_case "vapt-rootlink-lib-${target//\//-}"
    mkdir -p "$PACKAGE/usr/lib/systemd/system" "$PACKAGE/opt/subject/systemd"
    printf '[Service]\nExecStart=/usr/bin/subject\n' >"$PACKAGE/usr/lib/systemd/system/subject.service"
    ln -s "$target" "$PACKAGE/lib"
    repack
    review
    if [[ $target == opt/subject ]]; then
        assert_status "lib -> $target is refused" 1 "$STATUS"
        assert_contains "lib -> $target refusal names the link" "$OUTPUT" "replaces a systemd unit directory lib"
    else
        assert_status "lib -> $target is provisionable" 0 "$STATUS"
    fi
    vapt_tools_untouched "lib -> $target"
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
