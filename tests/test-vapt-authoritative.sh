# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Read-only metadata CLI regressions for libalpm's effective root semantics.
# All package helpers/hooks are fixture data; no payload or manager is executed.
source "$FIXTURES/vapt-lib.sh"

authoritative_case() {
    vapt_sandbox "$1"
    vapt_root
    export LC_ALL=C
    vapt_package subject 2-1
    AUTH_PACKAGE="$SANDBOX/packages/subject"
    AUTH_ARCHIVE="$SANDBOX/archives/subject-2-1-x86_64.pkg.tar.gz"
    # Honest package metadata, not a mocked audit/provenance response.
    printf 'url = https://example.org/subject\n' >>"$AUTH_PACKAGE/.PKGINFO"
}
authoritative_repack() {
    tar -czf "$SANDBOX/archives/$1-2-1-x86_64.pkg.tar.gz" -C "$SANDBOX/packages/$1" .
}
authoritative_hook() { # FILE OPERATION TYPE TARGET [EXEC]
    mkdir -p "${1%/*}"
    printf '[Trigger]\nOperation = %s\nType = %s\nTarget = %s\n[Action]\nWhen = PostTransaction\nExec = %s\n' \
        "$2" "$3" "$4" "${5:-/usr/bin/systemctl start subject.socket}" >"$1"
}
authoritative_helper() { # FILE inert|activating
    mkdir -p "${1%/*}"
    if [[ $2 == inert ]]; then
        printf '#!/bin/sh\nexit 0\n' >"$1"
    else
        printf '#!/bin/sh\nsystemctl start subject.socket\n' >"$1"
    fi
    chmod +x "$1"
}
authoritative_review() { # LABEL EXPECTED_STATUS [ARCHIVE...]
    local label="$1" expected="$2"
    shift 2
    if (($# == 0)); then set -- "$AUTH_ARCHIVE"; fi
    capture python3 "$VAPT_META" audit "$@" --root "$ROOT"
    assert_status "$label" "$expected" "$STATUS"
    assert_eq "$label: read-only audit executes no fixture command" '' "$(find "$CALLS" -type f -printf '%f\n')"
}
# auth_stock_shell — package scriptlets run through the base-proven /bin/sh:
# seed the stock owners (bash, its libraries and base-signed references) after
# the installed rows, without the stock hooks.
auth_stock_shell() {
    vapt_stock
    rm -f "$ROOT"/usr/share/libalpm/hooks/*.hook
}

# S1/DEEP1: old-only inventory is not proof of physical removal. Retain all
# parent directories and a sibling so only NoUpgrade's hook protection differs.
# Last matching exception wins both within a directive and across directives.
for variant in protected exception-last protection-last exception-directive protection-directive unprotected; do
    authoritative_case "vapt-authoritative-noupgrade-$variant"
    hook=usr/share/libalpm/hooks/activate.hook
    vapt_installed "subject|1-1|https://example.org/subject||||usr/,usr/bin/,usr/bin/subject,usr/share/,usr/share/libalpm/,usr/share/libalpm/hooks/,usr/share/libalpm/hooks/README,$hook"
    mkdir -p "$AUTH_PACKAGE/usr/share/libalpm/hooks"
    printf 'ordinary retained sibling\n' >"$AUTH_PACKAGE/usr/share/libalpm/hooks/README"
    authoritative_hook "$ROOT/$hook" Upgrade Package subject
    expected=1
    case "$variant" in
    protected) rules="$hook" ;;
    exception-last) rules="usr/share/libalpm/hooks/* !$hook"; expected=0 ;;
    protection-last) rules="!$hook usr/share/libalpm/hooks/*" ;;
    exception-directive) rules="usr/share/libalpm/hooks/*"$'\n'"NoUpgrade = !$hook"; expected=0 ;;
    protection-directive) rules="!$hook"$'\n'"NoUpgrade = usr/share/libalpm/hooks/*" ;;
    unprotected) rules='usr/share/libalpm/hooks/unrelated.hook'; expected=0 ;;
    esac
    vapt_conf_add "[options]"$'\n'"NoUpgrade = $rules"
    authoritative_repack subject
    authoritative_review "S1 $variant old-only post hook follows NoUpgrade retention" "$expected"
done

# S2/DEEP5: only a grammar-valid hook can mask a lower-priority basename.
# Invalid future hooks must be validated even when their trigger cannot match,
# or when they contain no trigger at all. The lower hook runs only post-install.
for relevance in nonmatching triggerless; do
    for invalid in garbage unknown-key unknown-section missing-exec unmatched-exec; do
        authoritative_case "vapt-authoritative-mask-$relevance-$invalid"
        authoritative_hook "$ROOT/usr/share/libalpm/hooks/activate.hook" Install Package subject
        high="$AUTH_PACKAGE/etc/pacman.d/hooks/activate.hook"
        mkdir -p "${high%/*}"
        if [[ $relevance == nonmatching ]]; then
            printf '[Trigger]\nOperation = Install\nType = Package\nTarget = unrelated\n' >"$high"
        else
            : >"$high"
        fi
        if [[ $invalid == missing-exec ]]; then
            printf '[Action]\nWhen = PostTransaction\n' >>"$high"
        elif [[ $invalid == unmatched-exec ]]; then
            printf '[Action]\nWhen = PostTransaction\nExec = /usr/bin/subject "unterminated\n' >>"$high"
        else
            printf '[Action]\nWhen = PostTransaction\nExec = /usr/bin/subject\n' >>"$high"
            case "$invalid" in
            garbage) printf 'garbage\n' >>"$high" ;;
            unknown-key) printf 'Bogus = yes\n' >>"$high" ;;
            unknown-section) printf '[Bogus]\nSomething = yes\n' >>"$high" ;;
            esac
        fi
        authoritative_helper "$AUTH_PACKAGE/usr/bin/subject" inert
        authoritative_repack subject
        if [[ $relevance == triggerless && $invalid == missing-exec ]]; then
            # libalpm validates triggerless dummy masks before requiring Exec.
            authoritative_review 'S2 valid triggerless mask needs no Exec' 0
        else
            authoritative_review "S2 $relevance $invalid cannot hide lower activating hook" 1
        fi
    done
done
# The pure garbage vector has no section/action as well as no trigger.
authoritative_case vapt-authoritative-mask-pure-garbage
authoritative_hook "$ROOT/usr/share/libalpm/hooks/activate.hook" Install Package subject
mkdir -p "$AUTH_PACKAGE/etc/pacman.d/hooks"
printf 'garbage\n' >"$AUTH_PACKAGE/etc/pacman.d/hooks/activate.hook"
authoritative_repack subject
authoritative_review 'DEEP5 bare garbage cannot become a basename mask' 1
for valid in triggerless nonmatching; do
    authoritative_case "vapt-authoritative-mask-valid-$valid"
    authoritative_hook "$ROOT/usr/share/libalpm/hooks/activate.hook" Install Package subject
    high="$AUTH_PACKAGE/etc/pacman.d/hooks/activate.hook"
    mkdir -p "${high%/*}"
    if [[ $valid == nonmatching ]]; then
        printf '[Trigger]\nOperation = Install\nType = Package\nTarget = unrelated\n' >"$high"
    else
        : >"$high"
    fi
    printf '[Action]\nWhen = PostTransaction\nExec = /usr/bin/subject\n' >>"$high"
    authoritative_helper "$AUTH_PACKAGE/usr/bin/subject" inert
    authoritative_repack subject
    authoritative_review "S2 valid $valid hook legitimately masks lower activation" 0
done

# DEEP2: INI comments are leading-only. Inline hashes remain literal path data
# for both current and newly shipped hooks; a plain-name payload is a nonmatch.
for location in existing incoming; do
    for payload in hash plain; do
        authoritative_case "vapt-authoritative-hash-$location-$payload"
        hook="$ROOT/usr/share/libalpm/hooks/hash.hook"
        [[ $location != incoming ]] || hook="$AUTH_PACKAGE/usr/share/libalpm/hooks/hash.hook"
        authoritative_hook "$hook" Install Path 'usr/share/subject/item#tag'
        # Commented-out activating/invalid lines must not change hook grammar.
        printf '  # Bogus = yes\n# [NotASection]\n' >>"$hook"
        mkdir -p "$AUTH_PACKAGE/usr/share/subject"
        name=item
        [[ $payload != hash ]] || name='item#tag'
        printf 'ordinary path data\n' >"$AUTH_PACKAGE/usr/share/subject/$name"
        authoritative_repack subject
        expected=0
        [[ $payload != hash ]] || expected=1
        authoritative_review "DEEP2 $location hash target with $payload payload" "$expected"
    done
done
# NoExtract's literal hash changes an existing path from Upgrade to Remove.
# The plain-name rule must not suppress the hash-containing event.
for rule in hash plain; do
    for operation in Remove Upgrade; do
        authoritative_case "vapt-authoritative-noextract-hash-$rule-$operation"
        vapt_installed 'subject|1-1|https://example.org/subject||||usr/bin/subject,usr/share/subject/item#tag'
        mkdir -p "$AUTH_PACKAGE/usr/share/subject"
        printf 'ordinary replacement data\n' >"$AUTH_PACKAGE/usr/share/subject/item#tag"
        pattern=usr/share/subject/item
        [[ $rule != hash ]] || pattern='usr/share/subject/item#tag'
        vapt_conf_add "[options]"$'\n'"  # NoExtract = usr/bin/subject"$'\n'"NoExtract = $pattern"
        authoritative_hook "$ROOT/usr/share/libalpm/hooks/hash.hook" "$operation" Path 'usr/share/subject/item#tag'
        authoritative_repack subject
        expected=0
        if [[ $rule == hash && $operation == Remove || $rule == plain && $operation == Upgrade ]]; then expected=1; fi
        authoritative_review "DEEP2 NoExtract $rule rule yields $operation hash event" "$expected"
    done
done
# Hashes in effective directory values must not discard incoming hooks either.
authoritative_case vapt-authoritative-hookdir-hash
vapt_conf_add $'[options]\nHookDir = /opt/site#hooks'
mkdir -p "$AUTH_PACKAGE/opt/site#hooks"
authoritative_repack subject
authoritative_review 'DEEP2 literal hash HookDir without hook is safe' 0
authoritative_hook "$AUTH_PACKAGE/opt/site#hooks/activate.hook" Install Package subject
authoritative_repack subject
authoritative_review 'DEEP2 literal hash HookDir includes incoming activating hook' 1

# S3: receiver depends on subject>=2, so subject's scriptlet runs before the
# receiver upgrade. Archive argument ordering is not package commit ordering.
# Both differing helper snapshots must be inspected conservatively; identical
# benign snapshots are the non-vacuous control. No helper is ever executed.
for phase in pre_upgrade post_upgrade; do
    for order in subject-first receiver-first; do
        for bytes in current-activating incoming-activating stable-benign; do
            authoritative_case "vapt-authoritative-crosspkg-$phase-$order-$bytes"
            vapt_installed 'subject|1-1|https://example.org/subject||||usr/bin/subject' \
                'receiver|1-1|https://example.org/receiver||subject>=1||usr/bin/receiver,usr/lib/receiver/setup'
            auth_stock_shell
            vapt_package receiver 2-1
            receiver_package="$SANDBOX/packages/receiver"
            receiver_archive="$SANDBOX/archives/receiver-2-1-x86_64.pkg.tar.gz"
            printf 'url = https://example.org/receiver\ndepend = subject>=2\n' >>"$receiver_package/.PKGINFO"
            printf '%s() {\n /usr/lib/receiver/setup\n}\n' "$phase" >"$AUTH_PACKAGE/.INSTALL"
            current=inert
            incoming=inert
            expected=1
            case "$bytes" in
            current-activating) current=activating ;;
            incoming-activating) incoming=activating ;;
            stable-benign) expected=0 ;;
            esac
            authoritative_helper "$ROOT/usr/lib/receiver/setup" "$current"
            authoritative_helper "$receiver_package/usr/lib/receiver/setup" "$incoming"
            authoritative_repack subject
            authoritative_repack receiver
            archives=("$AUTH_ARCHIVE" "$receiver_archive")
            [[ $order != receiver-first ]] || archives=("$receiver_archive" "$AUTH_ARCHIVE")
            authoritative_review "S3 $phase $order $bytes cross-package snapshots" "$expected" "${archives[@]}"
        done
    done
done
# Keep own-package phase controls adjacent: conservative cross-package handling
# must not collapse known own pre/current and own post/incoming snapshots.
for phase in pre_upgrade post_upgrade; do
    for current in activating inert; do
        authoritative_case "vapt-authoritative-ownpkg-$phase-$current"
        vapt_installed 'subject|1-1|https://example.org/subject||||usr/bin/subject,usr/lib/subject/setup'
        auth_stock_shell
        printf '%s() {\n /usr/lib/subject/setup\n}\n' "$phase" >"$AUTH_PACKAGE/.INSTALL"
        incoming=activating
        [[ $current != activating ]] || incoming=inert
        authoritative_helper "$ROOT/usr/lib/subject/setup" "$current"
        authoritative_helper "$AUTH_PACKAGE/usr/lib/subject/setup" "$incoming"
        authoritative_repack subject
        expected=0
        if [[ $phase == pre_upgrade && $current == activating || $phase == post_upgrade && $current == inert ]]; then expected=1; fi
        authoritative_review "S3 own-package $phase keeps $current current snapshot semantics" "$expected"
    done
done

# DEEP3: libalpm be_package.c build_filelist_from_mtree uses libarchive's mtree
# reader, strips ./, and replaces the tar-derived filelist after parsing.
# #mtree, /set, type=dir/file, size and octal mode are real mtree grammar.
# Construct compressed .MTREE bytes, not a fake bsdtar/metadata output.
authoritative_mtree() { # base|extra-event|matching-event
    {
        printf '#mtree\n/set uid=0 gid=0 mode=755\n'
        printf './.PKGINFO type=file size=%s\n' "$(stat -c %s "$AUTH_PACKAGE/.PKGINFO")"
        printf './usr type=dir\n./usr/bin type=dir\n'
        printf './usr/bin/subject type=file size=%s\n' "$(stat -c %s "$AUTH_PACKAGE/usr/bin/subject")"
        if [[ $1 != base ]]; then
            printf './usr/share type=dir\n./usr/share/subject type=dir\n'
            printf './usr/share/subject/trigger type=file size=0 mode=644\n'
        fi
    } | gzip -n >"$AUTH_PACKAGE/.MTREE"
}
for inventory in extra-event matching-event base; do
    authoritative_case "vapt-authoritative-mtree-$inventory"
    authoritative_hook "$ROOT/usr/share/libalpm/hooks/mtree.hook" Install Path usr/share/subject/trigger
    if [[ $inventory == matching-event ]]; then
        mkdir -p "$AUTH_PACKAGE/usr/share/subject"
        : >"$AUTH_PACKAGE/usr/share/subject/trigger"
    fi
    authoritative_mtree "$inventory"
    authoritative_repack subject
    expected=1
    [[ $inventory != base ]] || expected=0
    authoritative_review "DEEP3 $inventory compressed MTREE effective path event" "$expected"
done
# Matching metadata/payload stays provisionable when there is no relevant hook.
authoritative_case vapt-authoritative-mtree-matching-benign
mkdir -p "$AUTH_PACKAGE/usr/share/subject"
: >"$AUTH_PACKAGE/usr/share/subject/trigger"
authoritative_mtree matching-event
authoritative_hook "$ROOT/usr/share/libalpm/hooks/mtree.hook" Install Path usr/share/subject/unrelated
authoritative_repack subject
authoritative_review 'DEEP3 congruent MTREE and tar with nonmatching hook accepted' 0
for malformed in invalid-format invalid-type; do
    authoritative_case "vapt-authoritative-mtree-$malformed"
    if [[ $malformed == invalid-format ]]; then
        printf 'not an mtree archive\n' | gzip -n >"$AUTH_PACKAGE/.MTREE"
    else
        printf '#mtree\n./usr type=not-a-valid-type\n' | gzip -n >"$AUTH_PACKAGE/.MTREE"
    fi
    authoritative_repack subject
    authoritative_review "DEEP3 $malformed compressed MTREE cannot silently fall back" 1
done

# DEEP4: Hook Exec uses execv from /, not shell builtin/PATH lookup. Literal
# true and echo therefore name archive /true and /echo, including quoted argv.
for executable in true echo; do
    for spelling in relative absolute; do
        authoritative_case "vapt-authoritative-directexec-$executable-$spelling"
        authoritative_helper "$AUTH_PACKAGE/$executable" activating
        command="$executable"
        [[ $spelling != absolute ]] || command="/$executable"
        [[ $executable != echo ]] || command+=" 'ordinary message'"
        authoritative_hook "$AUTH_PACKAGE/usr/share/libalpm/hooks/direct.hook" Install Package subject "$command"
        authoritative_repack subject
        authoritative_review "DEEP4 $spelling $executable hook resolves actual activating program" 1
    done
done
authoritative_case vapt-authoritative-directexec-absolute-inert
authoritative_helper "$AUTH_PACKAGE/usr/lib/subject/setup" inert
authoritative_hook "$AUTH_PACKAGE/usr/share/libalpm/hooks/direct.hook" Install Package subject /usr/lib/subject/setup
authoritative_repack subject
authoritative_review 'DEEP4 absolute inspected inert hook helper is provisionable' 0
# The same root payloads are irrelevant to actual shell builtins in .INSTALL.
# Preserve the distinction rather than banning harmless shell provisioning.
for phase in pre_install post_install; do
    authoritative_case "vapt-authoritative-shell-builtins-$phase"
    auth_stock_shell
    authoritative_helper "$AUTH_PACKAGE/true" activating
    authoritative_helper "$AUTH_PACKAGE/echo" activating
    printf '%s() {\n true\n echo "ordinary message"\n}\n' "$phase" >"$AUTH_PACKAGE/.INSTALL"
    authoritative_repack subject
    authoritative_review "DEEP4 $phase shell true and echo remain builtins" 0
done
# A shell function overrides a builtin; its declaration cannot be discarded
# as an inactive package phase while a reachable call is treated as harmless.
for executable in true echo; do
    for phase in pre_install post_install; do
        authoritative_case "vapt-authoritative-function-override-$executable-$phase"
        printf '%s() {\n systemctl start forbidden.service\n}\n%s() {\n %s\n}\n' \
            "$executable" "$phase" "$executable" >"$AUTH_PACKAGE/.INSTALL"
        authoritative_repack subject
        authoritative_review "DEEP4 $phase activating $executable function is not a builtin" 1
    done
done

# Interpreter flags must preserve execution of the inspected body, rather than
# treating its filename as a command or reading unreviewed startup/stdin code.
for flag in c s i e u eu; do
    authoritative_case "vapt-authoritative-shebang-$flag"
    # The retained interpreter must be base-proven: an authenticated stock
    # bash owner (inert ELF metadata, base-signed reference), not a label.
    vapt_stock
    rm -f "$ROOT"/usr/share/libalpm/hooks/*.hook
    executable="/usr/bin/syst'em'ctl st'art' subject.socket"
    printf '#!/bin/bash -%s\nexit 0\n' "$flag" >"$AUTH_PACKAGE$executable"
    chmod +x "$AUTH_PACKAGE$executable"
    authoritative_hook "$AUTH_PACKAGE/usr/share/libalpm/hooks/direct.hook" Install Package subject "\"$executable\""
    authoritative_repack subject
    expected=1
    [[ $flag != e && $flag != u && $flag != eu ]] || expected=0
    authoritative_review "helper shebang -$flag preserves reviewed file-body semantics" "$expected"
done

# No real compressor is run: the fixture archiver records and refuses an
# option-position program request. Literal extraction must reveal activation.
authoritative_case vapt-authoritative-member-option
executable='/--use-compress-program=/usr/bin/id'
authoritative_helper "$AUTH_PACKAGE$executable" activating
authoritative_hook "$AUTH_PACKAGE/usr/share/libalpm/hooks/direct.hook" Install Package subject "$executable"
tar -czf "$AUTH_ARCHIVE" -C "$AUTH_PACKAGE" -- .PKGINFO usr '--use-compress-program='
authoritative_review 'archive helper member cannot become a compressor option' 1

# Bash treats a hash inside a word literally; a decoy prefix must not hide
# the called helper or turn a different program name into a builtin.
for caller in scriptlet helper builtin-prefix; do
    authoritative_case "vapt-authoritative-shell-hash-$caller"
    authoritative_helper "$AUTH_PACKAGE/usr/lib/subject/next" inert
    authoritative_helper "$AUTH_PACKAGE/usr/lib/subject/next#active" activating
    if [[ $caller == builtin-prefix ]]; then
        authoritative_helper "$AUTH_PACKAGE/usr/bin/true#active" activating
        printf 'post_install() {\n true#active\n}\n' >"$AUTH_PACKAGE/.INSTALL"
    elif [[ $caller == scriptlet ]]; then
        printf 'post_install() {\n /usr/lib/subject/next#active\n}\n' >"$AUTH_PACKAGE/.INSTALL"
    else
        printf '#!/bin/sh\n/usr/lib/subject/next#active\n' >"$AUTH_PACKAGE/usr/lib/subject/setup"
        chmod +x "$AUTH_PACKAGE/usr/lib/subject/setup"
        authoritative_hook "$AUTH_PACKAGE/usr/share/libalpm/hooks/direct.hook" Install Package subject /usr/lib/subject/setup
    fi
    authoritative_repack subject
    authoritative_review "shell $caller literal hash cannot hide activating execution" 1
done
