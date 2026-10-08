# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Real read-only archive-audit CLI against fake packages and fixture hooks.
# Hook actions and executable payloads are data: never execute them or a manager.
source "$FIXTURES/vapt-lib.sh"

alpm_case() {
    vapt_sandbox "$1"
    vapt_root
    export LC_ALL=C
    vapt_package subject 2-1
    ALPM_PACKAGE="$SANDBOX/packages/subject"
    ALPM_ARCHIVE="$SANDBOX/archives/subject-2-1-x86_64.pkg.tar.gz"
}
alpm_repack() { # NAME (all package files, including optional etc/opt payloads)
    tar -czf "$SANDBOX/archives/$1-2-1-x86_64.pkg.tar.gz" -C "$SANDBOX/packages/$1" .
}
alpm_hook() { # FILE OPERATION TYPE WHEN TARGET... (order is significant)
    local file="$1" operation="$2" kind="$3" when="$4" target
    shift 4
    mkdir -p "${file%/*}"
    {
        printf '[Trigger]\nOperation = %s\nType = %s\n' "$operation" "$kind"
        for target in "$@"; do printf 'Target = %s\n' "$target"; done
        printf '[Action]\nWhen = %s\nExec = /usr/bin/systemctl start subject.socket\n' "$when"
    } >"$file"
}
alpm_review() { # LABEL EXPECTED_STATUS [ARCHIVE...]
    local label="$1" expected="$2"
    shift 2
    if (($# == 0)); then set -- "$ALPM_ARCHIVE"; fi
    capture python3 "$VAPT_META" audit "$@" --root "$ROOT"
    assert_status "$label" "$expected" "$STATUS"
    # Audit must not execute any hook, package decoy, tool, key or manager.
    assert_eq "$label: audit executes no fixture command" '' "$(find "$CALLS" -type f -printf '%f\n')"
}
alpm_shared() {
    vapt_installed 'subject|1-1|https://example.org/||||usr/bin/subject,usr/lib/subject/shared'
    mkdir -p "$ALPM_PACKAGE/usr/lib/subject"
    printf 'ordinary shared package data\n' >"$ALPM_PACKAGE/usr/lib/subject/shared"
    alpm_repack subject
}

# SEC-R1: the real configuration accepts trailing slash, repeated slash and
# dot-component spellings. All must include newly supplied post-phase hooks.
# Ship an ordinary unit definition too: it alone does not activate a service.
for spelling in /etc/pacman.d/hooks /etc/pacman.d/hooks/ /etc//pacman.d/hooks/ /etc/pacman.d/./hooks/; do
    alpm_case "vapt-alpm-hookdir-${spelling//\//-}"
    vapt_conf_add "[options]"$'\n'"HookDir = $spelling"
    mkdir -p "$ALPM_PACKAGE/usr/lib/systemd/system"
    printf '[Socket]\nListenStream=43210\n' >"$ALPM_PACKAGE/usr/lib/systemd/system/subject.socket"
    alpm_repack subject
    alpm_review "$spelling ordinary socket definition is provisionable" 0
    alpm_hook "$ALPM_PACKAGE/etc/pacman.d/hooks/activate.hook" Install Package PostTransaction subject
    alpm_repack subject
    alpm_review "SEC-R1 $spelling incoming post hook cannot disappear" 1
done

# HookDir is not restricted to a directory literally named "hooks".
alpm_case vapt-alpm-custom-hookdir
vapt_conf_add $'[options]\nHookDir = /opt/site-hooks/'
alpm_review 'custom effective hook directory without hooks is provisionable' 0
alpm_hook "$ALPM_PACKAGE/opt/site-hooks/activate.hook" Install Package PostTransaction subject
alpm_repack subject
alpm_review 'custom effective hook directory includes incoming activation hook' 1

# Masks are basename- and directory-priority-specific, even with slash aliases.
for mask in later earlier different-name; do
    alpm_case "vapt-alpm-trailing-mask-$mask"
    mkdir -p "$ROOT/opt/late-hooks" "$ROOT/opt/early-hooks"
    if [[ $mask == earlier ]]; then
        vapt_conf_add $'[options]\nHookDir = /opt/early-hooks/ /etc/pacman.d/hooks/'
        ln -s /dev/null "$ROOT/opt/early-hooks/activate.hook"
    else
        vapt_conf_add $'[options]\nHookDir = /etc/pacman.d/hooks/ /opt/late-hooks/'
        basename=activate.hook
        [[ $mask != different-name ]] || basename=unrelated.hook
        ln -s /dev/null "$ROOT/opt/late-hooks/$basename"
    fi
    alpm_hook "$ALPM_PACKAGE/etc/pacman.d/hooks/activate.hook" Install Package PostTransaction subject
    alpm_repack subject
    expected=1
    [[ $mask != later ]] || expected=0
    alpm_review "SEC-R1 $mask mask obeys effective hook priority" "$expected"
done

# Incoming PreTransaction hooks are not run retroactively. Replacing current
# hooks cannot hide the current pre action, nor retain an obsolete post action.
for phase in PreTransaction PostTransaction; do
    alpm_case "vapt-alpm-incoming-$phase"
    vapt_conf_add $'[options]\nHookDir = /etc/pacman.d/hooks/'
    alpm_hook "$ALPM_PACKAGE/etc/pacman.d/hooks/activate.hook" Install Package "$phase" subject
    alpm_repack subject
    expected=1
    [[ $phase != PreTransaction ]] || expected=0
    alpm_review "incoming $phase hook uses correct temporal view" "$expected"
done
for phase in PreTransaction PostTransaction; do
    alpm_case "vapt-alpm-replaced-$phase"
    vapt_conf_add $'[options]\nHookDir = /etc/pacman.d/hooks/'
    vapt_installed 'subject|1-1|https://example.org/||||usr/bin/subject,etc/pacman.d/hooks/activate.hook'
    alpm_hook "$ROOT/etc/pacman.d/hooks/activate.hook" Upgrade Package "$phase" subject
    alpm_hook "$ALPM_PACKAGE/etc/pacman.d/hooks/activate.hook" Upgrade Package "$phase" subject
    # Same trigger, inert future action. Only the current pre action is unsafe.
    printf '[Trigger]\nOperation = Upgrade\nType = Package\nTarget = subject\n[Action]\nWhen = %s\nExec = /usr/bin/subject\n' "$phase" \
        >"$ALPM_PACKAGE/etc/pacman.d/hooks/activate.hook"
    # Replace the subject logging decoy with an auditable, never-run inert helper.
    printf '#!/bin/sh\nexit 0\n' >"$ALPM_PACKAGE/usr/bin/subject"
    alpm_repack subject
    expected=0
    [[ $phase != PreTransaction ]] || expected=1
    alpm_review "replacement $phase hook cannot confuse current and future bytes" "$expected"
done

# SEC-R2: NoExtract changes hook operation membership, not necessarily whether
# the old physical file is deleted. The retained old path is a Remove candidate.
for operation in Remove Install Upgrade; do
    alpm_case "vapt-alpm-noextract-shared-$operation"
    alpm_shared
    vapt_conf_add $'[options]\nNoExtract = usr/lib/subject/shared'
    alpm_hook "$ROOT/usr/share/libalpm/hooks/path.hook" "$operation" Path PostTransaction usr/lib/subject/shared
    expected=0
    [[ $operation != Remove ]] || expected=1
    alpm_review "SEC-R2 NoExtract shared path has $operation relevance" "$expected"
done

# The last matching NoExtract exception wins across and within directives.
# Nonmatching later rules must not erase the last matching result.
for variant in extract-last suppress-last extract-last-directive suppress-last-directive nonmatch; do
    alpm_case "vapt-alpm-noextract-order-$variant"
    alpm_shared
    case "$variant" in
    extract-last) rules='usr/lib/subject/* !usr/lib/subject/shared' ;;
    suppress-last) rules='!usr/lib/subject/shared usr/lib/subject/*' ;;
    extract-last-directive) rules=$'usr/lib/subject/*\nNoExtract = !usr/lib/subject/shared' ;;
    suppress-last-directive) rules=$'!usr/lib/subject/shared\nNoExtract = usr/lib/subject/*' ;;
    nonmatch) rules='usr/lib/subject/shared !usr/lib/subject/absent' ;;
    esac
    vapt_conf_add "[options]"$'\n'"NoExtract = $rules"
    for operation in Remove Upgrade; do
        alpm_hook "$ROOT/usr/share/libalpm/hooks/path.hook" "$operation" Path PostTransaction usr/lib/subject/shared
        expected=0
        if [[ $variant == extract-last* && $operation == Upgrade || $variant != extract-last* && $operation == Remove ]]; then expected=1; fi
        alpm_review "NoExtract $variant yields $operation relevance" "$expected"
    done
done
alpm_case vapt-alpm-noupgrade-shared
alpm_shared
vapt_conf_add $'[options]\nNoUpgrade = usr/lib/subject/shared'
alpm_hook "$ROOT/usr/share/libalpm/hooks/path.hook" Upgrade Path PostTransaction usr/lib/subject/shared
alpm_review 'NoUpgrade does not remove shared path from the Upgrade hook set' 1

# An excluded new-only path has no hook event; old-only paths remain Remove.
for path in new old; do
    alpm_case "vapt-alpm-noextract-$path"
    vapt_installed 'subject|1-1|https://example.org/||||usr/bin/subject,usr/lib/subject/old'
    mkdir -p "$ALPM_PACKAGE/usr/lib/subject"
    printf 'ordinary new data\n' >"$ALPM_PACKAGE/usr/lib/subject/new"
    vapt_conf_add $'[options]\nNoExtract = usr/lib/subject/*'
    alpm_repack subject
    for operation in Install Remove Upgrade; do
        alpm_hook "$ROOT/usr/share/libalpm/hooks/path.hook" "$operation" Path PostTransaction "usr/lib/subject/$path"
        expected=0
        if [[ $path == old && $operation == Remove ]]; then expected=1; fi
        alpm_review "NoExtract $path-only path has $operation relevance" "$expected"
    done
done

# A legal file move is Upgrade globally: sender drops a path and receiver
# supplies it. Exercise both new/existing receiver and both archive orders.
for receiver in new existing; do
    for order in sender-first receiver-first; do
        alpm_case "vapt-alpm-move-$receiver-$order"
        old_subject='subject|1-1|https://example.org/||||usr/bin/subject,usr/lib/subject/shared'
        if [[ $receiver == existing ]]; then
            vapt_installed "$old_subject" 'receiver|1-1|https://example.org/||||usr/bin/receiver'
        else
            vapt_installed "$old_subject"
        fi
        vapt_package receiver 2-1
        mkdir -p "$SANDBOX/packages/receiver/usr/lib/subject"
        printf 'ordinary transferred data\n' >"$SANDBOX/packages/receiver/usr/lib/subject/shared"
        alpm_repack receiver
        receiver_archive="$SANDBOX/archives/receiver-2-1-x86_64.pkg.tar.gz"
        archives=("$ALPM_ARCHIVE" "$receiver_archive")
        [[ $order != receiver-first ]] || archives=("$receiver_archive" "$ALPM_ARCHIVE")
        for operation in Install Remove Upgrade; do
            alpm_hook "$ROOT/usr/share/libalpm/hooks/path.hook" "$operation" Path PostTransaction usr/lib/subject/shared
            expected=0
            [[ $operation != Upgrade ]] || expected=1
            alpm_review "SEC-R2 $receiver receiver $order file move has $operation relevance" "$expected" "${archives[@]}"
        done
        # Suppressing the receiving payload changes the same transaction to Remove.
        vapt_conf_add $'[options]\nNoExtract = usr/lib/subject/shared'
        for operation in Remove Upgrade; do
            alpm_hook "$ROOT/usr/share/libalpm/hooks/path.hook" "$operation" Path PostTransaction usr/lib/subject/shared
            expected=0
            [[ $operation != Remove ]] || expected=1
            alpm_review "$receiver receiver $order NoExtract move has $operation relevance" "$expected" "${archives[@]}"
        done
    done
done

# SEC-R3: a later matching positive overrides an earlier exclusion for either
# Package or Path; inverse ordering and a negative-only trigger are irrelevant.
for kind in Package Path; do
    for operation in Install Upgrade; do
        alpm_case "vapt-alpm-target-order-$kind-$operation"
        [[ $operation != Upgrade ]] || alpm_shared
        target=subject
        [[ $kind != Path ]] || target=usr/bin/subject
        for variant in positive-last negative-last later-nonmatch negative-only; do
            case "$variant" in
            positive-last) targets=("!$target" "$target") ;;
            negative-last) targets=("$target" "!$target") ;;
            later-nonmatch) targets=("!$target" "$target" '!unrelated') ;;
            negative-only) targets=("!$target") ;;
            esac
            alpm_hook "$ROOT/usr/share/libalpm/hooks/ordered.hook" "$operation" "$kind" PostTransaction "${targets[@]}"
            expected=0
            [[ $variant != positive-last && $variant != later-nonmatch ]] || expected=1
            alpm_review "SEC-R3 $kind $operation $variant target precedence" "$expected"
        done
    done
done

# libalpm uses libc fnmatch, not Python's superficially similar glob language.
# Cover active matches and genuine nonmatches, plus exceptions in each order.
for syntax in posix-class negated-class escape-ordinary escaped-star escaped-question slash-wildcard; do
    alpm_case "vapt-alpm-target-libc-$syntax"
    kind=Package
    target=subject
    case "$syntax" in
    posix-class) pattern='sub[[:alpha:]]ect'; nonmatch='sub[[:digit:]]ect' ;;
    negated-class) pattern='sub[^a]ect'; nonmatch='sub[^j]ect' ;;
    escape-ordinary) pattern='sub\ject'; nonmatch='sub\aect' ;;
    escaped-star) kind=Path; target='usr/lib/subject/item*'; pattern='usr/lib/subject/item\*'; nonmatch='usr/lib/subject/item\?' ;;
    escaped-question) kind=Path; target='usr/lib/subject/item?'; pattern='usr/lib/subject/item\?'; nonmatch='usr/lib/subject/item\*' ;;
    slash-wildcard) kind=Path; target='usr/lib/subject/shared'; pattern='usr/*/shared'; nonmatch='usr/*/absent' ;;
    esac
    if [[ $kind == Path ]]; then
        mkdir -p "$ALPM_PACKAGE/usr/lib/subject"
        printf 'ordinary pattern fixture data\n' >"$ALPM_PACKAGE/$target"
        alpm_repack subject
    fi
    alpm_hook "$ROOT/usr/share/libalpm/hooks/pattern.hook" Install "$kind" PostTransaction "$pattern"
    alpm_review "$syntax libc matching Target activates and must be rejected" 1
    alpm_hook "$ROOT/usr/share/libalpm/hooks/pattern.hook" Install "$kind" PostTransaction "$nonmatch"
    alpm_review "$syntax libc nonmatching Target remains provisionable" 0
    alpm_hook "$ROOT/usr/share/libalpm/hooks/pattern.hook" Install "$kind" PostTransaction "!$pattern" "$target"
    alpm_review "$syntax exclusion before exact inclusion is overridden" 1
    alpm_hook "$ROOT/usr/share/libalpm/hooks/pattern.hook" Install "$kind" PostTransaction "$target" "!$pattern"
    alpm_review "$syntax final matching exclusion makes hook irrelevant" 0
done

# NoExtract and Target must agree on libc matching syntax. A class-matched or
# escaped ordinary-character NoExtract rule changes shared Upgrade to Remove.
for syntax in posix-class escape-ordinary; do
    alpm_case "vapt-alpm-noextract-libc-$syntax"
    alpm_shared
    pattern='usr/lib/subject/sh[[:alpha:]]red'
    [[ $syntax != escape-ordinary ]] || pattern='usr/lib/subject/sh\ared'
    vapt_conf_add "[options]"$'\n'"NoExtract = $pattern"
    for operation in Remove Upgrade; do
        alpm_hook "$ROOT/usr/share/libalpm/hooks/path.hook" "$operation" Path PostTransaction usr/lib/subject/shared
        expected=0
        [[ $operation != Remove ]] || expected=1
        alpm_review "$syntax NoExtract has $operation relevance" "$expected"
    done
done

# libalpm strips one escape before a positive pattern beginning with "!";
# two leading bangs mean exclusion of a path whose actual name starts with !.
alpm_case vapt-alpm-target-literal-leading-bang
printf 'ordinary leading-bang path data\n' >"$ALPM_PACKAGE/!subject"
alpm_repack subject
alpm_hook "$ROOT/usr/share/libalpm/hooks/bang.hook" Install Path PostTransaction '\!subject'
alpm_review 'escaped leading bang is a positive literal Path target' 1
alpm_hook "$ROOT/usr/share/libalpm/hooks/bang.hook" Install Path PostTransaction '!!subject' '\!subject'
alpm_review 'escaped leading bang inclusion overrides earlier literal exclusion' 1
alpm_hook "$ROOT/usr/share/libalpm/hooks/bang.hook" Install Path PostTransaction '\!subject' '!!subject'
alpm_review 'final literal leading bang exclusion makes Path hook irrelevant' 0
alpm_hook "$ROOT/usr/share/libalpm/hooks/bang.hook" Install Path PostTransaction '\!absent'
alpm_review 'escaped leading bang nonmatch remains provisionable' 0

# The same escaped leading-bang rule must suppress effective incoming paths.
alpm_case vapt-alpm-noextract-literal-leading-bang
vapt_installed 'subject|1-1|https://example.org/||||usr/bin/subject,!subject'
printf 'ordinary leading-bang replacement data\n' >"$ALPM_PACKAGE/!subject"
vapt_conf_add $'[options]\nNoExtract = \\!subject'
alpm_repack subject
for operation in Remove Upgrade; do
    alpm_hook "$ROOT/usr/share/libalpm/hooks/bang.hook" "$operation" Path PostTransaction '\!subject'
    expected=0
    [[ $operation != Remove ]] || expected=1
    alpm_review "escaped leading bang NoExtract has $operation relevance" "$expected"
done
