# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# VAPT trust and transaction safety (plan 007): BlackArch keyring signature
# vectors and what a rejection leaves untouched, the interrupted-upgrade
# guard, the transaction pacman configuration, solver-plan closure and package
# archive audit. Fixture data only: curl serves fixture files, gpg replays a
# recorded status vector, sudo records without acting.
# shellcheck source=tests/fixtures/vapt-lib.sh
source "$FIXTURES/vapt-lib.sh"

WHOIS="extra|whois|5.6.4-1|https://github.com/rfc1036/whois"
SIGNERS="$VAPT_LAYER/files/blackarch-signers.txt"
mapfile -t PRIMARIES < <(grep -E '^[A-F0-9]{40}$' "$SIGNERS")
P="${PRIMARIES[0]}"
Q="${PRIMARIES[1]}"
SUB=0123456789ABCDEF0123456789ABCDEF01234567
OTHER=FEDCBA9876543210FEDCBA9876543210FEDCBA98

# validsig SIGNING_FPR PRIMARY_FPR — a gpg VALIDSIG status line.
validsig() { printf '[GNUPG:] VALIDSIG %s 2026-10-01 1790812800 0 4 0 22 10 00 %s\n' "$1" "$2"; }
HEAD=$'[GNUPG:] NEWSIG\n[GNUPG:] KEY_CONSIDERED '"$P"$' 0\n'
GOOD="[GNUPG:] GOODSIG ${P:24} BlackArch signer"$'\n'
TRUST=$'[GNUPG:] TRUST_UNDEFINED 0 pgp\n'
declare -A VECTOR=(
    [approved]="$HEAD$GOOD$(validsig "$SUB" "$P")"$'\n'"$TRUST"
    [bad]="${HEAD}[GNUPG:] BADSIG ${P:24} BlackArch signer"$'\n'
    [bad-after-good]="$HEAD$GOOD$(validsig "$SUB" "$P")"$'\n'"[GNUPG:] NEWSIG"$'\n'"[GNUPG:] BADSIG ${P:24} BlackArch signer"$'\n'
    [revoked]="${HEAD}[GNUPG:] REVKEYSIG ${P:24} BlackArch signer"$'\n'"$(validsig "$SUB" "$P")"$'\n'
    [key-revoked]="${HEAD}[GNUPG:] KEYREVOKED"$'\n'"$GOOD$(validsig "$SUB" "$P")"$'\n'
    [expired-key]="${HEAD}[GNUPG:] EXPKEYSIG ${P:24} BlackArch signer"$'\n'"$(validsig "$SUB" "$P")"$'\n'
    [expired-sig]="${HEAD}[GNUPG:] EXPSIG ${P:24} BlackArch signer"$'\n'"$(validsig "$SUB" "$P")"$'\n'
    [ambiguous]="$HEAD$GOOD$(validsig "$SUB" "$P")"$'\n'"$(validsig "$OTHER" "$Q")"$'\n'
    [unapproved]="$HEAD$GOOD$(validsig "$SUB" "$OTHER")"$'\n'
    [approved-subkey-only]="$HEAD$GOOD$(validsig "$P" "$OTHER")"$'\n'
    [no-validsig]="$HEAD$GOOD$TRUST"
    [missing-key]=$'[GNUPG:] NEWSIG\n[GNUPG:] ERRSIG 0123456789ABCDEF 22 10 00 1790812800 9 -\n[GNUPG:] NO_PUBKEY 0123456789ABCDEF\n'
    [injected]="gpg: [GNUPG:] $(validsig "$SUB" "$P")"$'\n'
    [malformed]=$'[GNUPG:] VALIDSIG '"$SUB 2026-10-01 1790812800"$'\n'
    [duplicate-approved]="$HEAD$GOOD$(validsig "$SUB" "$P")"$'\n'"$(validsig "$SUB" "$P")"$'\n'
    [expired-status]="$HEAD$GOOD$(validsig "$SUB" "$P")"$'\n'"[GNUPG:] SIGEXPIRED 1790812800"$'\n'
    [failure-after-valid]="$HEAD$GOOD$(validsig "$SUB" "$P")"$'\n'"[GNUPG:] FAILURE verify 1"$'\n'
)

# --- the signature decision itself -------------------------------------------
vapt_sandbox vapt-verify
for name in "${!VECTOR[@]}"; do
    printf '%s' "${VECTOR[$name]}" >"$SANDBOX/status"
    capture python3 "$VAPT_META" verify "$SANDBOX/status" "$SIGNERS"
    if [[ $name == approved ]]; then
        assert_status "signature $name: accepted" 0 "$STATUS"
        assert_eq "signature $name: the pinned primary is the signer" "$P" "$OUTPUT"
    else
        assert_status "signature $name: rejected" 1 "$STATUS"
    fi
done

# --- end to end: only an accepted signature reaches keyring trust ------------
# kr_case NAME VECTOR [SCRIPTLET] — a host without BlackArch; curl serves a
# fixture keyring database/package, gpg replays detached-signature status.
kr_case() {
    vapt_sandbox "$1"
    vapt_root
    printf '[options]\nArchitecture = auto\nSigLevel = Required DatabaseOptional\n\n[core]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n\n[extra]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n' \
        >"$ROOT/etc/pacman.conf"
    vapt_repos "${VAPT_BASE[@]}" "$WHOIS"
    vapt_sudo_noop
    # Mutating flows run through the hermetic runner (public CLI refuses a
    # sysroot); key and config operations are recorded fixture fakes.
    export VAPT_FAKE_TRUST=1
    printf '%s' "$2" >"$SANDBOX/vector"
    local kr="$SANDBOX/kr" file=blackarch-keyring-20251001-1-any.pkg.tar.zst
    mkdir -p "$kr/db/blackarch-keyring-20251001-1" "$kr/pkg/usr/share/pacman/keyrings"
    printf 'pkgname = blackarch-keyring\npkgver = 20251001-1\narch = any\n' >"$kr/pkg/.PKGINFO"
    printf 'fixture keyring\n' >"$kr/pkg/usr/share/pacman/keyrings/blackarch.gpg"
    local members=(.PKGINFO usr)
    if [[ -n ${3:-} ]]; then
        printf '%s\n' "$3" >"$kr/pkg/.INSTALL"
        members+=(.INSTALL)
    fi
    tar -czf "$kr/keyring.pkg" -C "$kr/pkg" "${members[@]}"
    # Like the real BlackArch DB, the record binds the artifact's digest.
    printf '%%FILENAME%%\n%s\n\n%%NAME%%\nblackarch-keyring\n\n%%VERSION%%\n20251001-1\n\n%%SHA256SUM%%\n%s\n\n' \
        "$file" "$(sha256sum "$kr/keyring.pkg" | cut -d' ' -f1)" >"$kr/db/blackarch-keyring-20251001-1/desc"
    tar -czf "$kr/blackarch.db" -C "$kr/db" blackarch-keyring-20251001-1
    cat >"$SANDBOX/stubs/curl" <<EOF
#!/bin/sh
# Serves fixture files for the BlackArch origin and keyserver; no network.
printf '%s\n' "\$*" >>'$CALLS/curl'
out='' url=''
while [ \$# -gt 0 ]; do
    case "\$1" in
    --output) out="\$2"; shift ;;
    --proto | --proto-redir) shift ;;
    *) url="\$1" ;;
    esac
    shift
done
case "\$url" in
*keyserver*) printf 'public key\n' >"\$out" ;;
*.sig) printf 'detached signature\n' >"\$out" ;;
*.db) cp '$kr/blackarch.db' "\$out" ;;
*.pkg.tar.zst) cp '$kr/keyring.pkg' "\$out" ;;
*) exit 22 ;;
esac
EOF
    cat >"$SANDBOX/stubs/gpg" <<EOF
#!/bin/sh
# Show-only import reports the requested primary; --verify replays the
# selected status vector. Nothing is imported, exported or trusted.
printf '%s\n' "\$*" >>'$CALLS/gpg'
status='' file='' verify=false showonly=false
while [ \$# -gt 0 ]; do
    case "\$1" in
    --status-file) status="\$2"; shift ;;
    --verify) verify=true ;;
    --import-options) [ "\$2" != show-only ] || showonly=true; shift ;;
    --homedir | --output | --export) shift ;;
    -*) ;;
    *) file="\$1" ;;
    esac
    shift
done
if \$verify; then cp '$SANDBOX/vector' "\$status"; exit 0; fi
if \$showonly; then
    fpr=\$(basename "\$file" .asc)
    printf 'pub:-:255:22:%s:1700000000:::-:::scESC::::::::0:\nfpr:::::::::%s:\n' "\$fpr" "\$fpr"
fi
exit 0
EOF
    chmod +x "$SANDBOX/stubs/curl" "$SANDBOX/stubs/gpg"
}
for name in approved bad revoked expired-key expired-sig ambiguous unapproved approved-subkey-only; do
    if [[ $name == approved ]] && ! command -v bsdtar >/dev/null 2>&1; then
        echo "  (note: bsdtar is not installed; the accepted-keyring control was skipped)"
        continue
    fi
    kr_case "vapt-keyring-$name" "${VECTOR[$name]}"
    vapt_api install --yes --groups api
    sudo_log="$(vapt_calls sudo)"
    if [[ $name == approved ]]; then
        assert_status "keyring $name: the pinned keyring is accepted (control)" 0 "$STATUS"
    else
        assert_status "keyring $name: a rejected source is unavailable, not a failed apply" 0 "$STATUS"
        assert_not_contains "keyring $name: no pacman-key trust change" "$sudo_log" "pacman-key"
        assert_not_contains "keyring $name: the keyring package is not installed" "$sudo_log" " -U "
        assert_not_contains "keyring $name: pacman.conf is not touched" "$sudo_log" "/etc/pacman.conf"
        assert_not_contains "keyring $name: no full upgrade is started" "$sudo_log" "-Syu"
        assert_not_contains "keyring $name: no signer key is exported" "$(vapt_calls gpg)" "--export"
    fi
    assert_eq "keyring $name: staging is cleaned up" "" "$(ls -A "$ROOT$XDG_CACHE_HOME/haseen/vapt" 2>/dev/null || true)"
    vapt_tools_untouched "keyring $name"
done

# The reviewed upstream population script is a narrow keyring-only exception;
# neither a changed payload nor a relevant host hook inherits that exception.
KEYRING_SCRIPT="$(cat "$FIXTURES/vapt-keyring.INSTALL")"
for variant in reviewed whitespace changed activation hook; do
    script="$KEYRING_SCRIPT"
    case "$variant" in
    whitespace) script="${script/--populate blackarch/--populate    blackarch}" ;;
    changed) script="${script/--populate blackarch/--populate other}" ;;
    activation) script+=$'\npost_install_extra() {\n systemctl enable evil.socket\n}' ;;
    esac
    kr_case "vapt-keyring-population-$variant" "${VECTOR[approved]}" "$script"
    if [[ $variant == hook ]]; then
        mkdir -p "$ROOT/etc/pacman.d/hooks"
        printf '[Trigger]\nOperation = Install\nType = Package\nTarget = blackarch-keyring\n[Action]\nWhen = PostTransaction\nExec = /usr/bin/systemctl enable evil.socket\n' \
            >"$ROOT/etc/pacman.d/hooks/unsafe.hook"
    fi
    vapt_api install --yes --groups api
    if [[ $variant == reviewed || $variant == whitespace ]]; then
        assert_status "$variant population script is accepted (control)" 0 "$STATUS"
    else
        assert_status "$variant keyring policy rejection is a source skip" 0 "$STATUS"
        assert_not_contains "$variant rejected before trust mutation" "$(vapt_calls sudo)" 'pacman-key'
        assert_not_contains "$variant rejected before package install" "$(vapt_calls sudo)" ' -U '
    fi
    vapt_tools_untouched "keyring population $variant"
done

vapt_sandbox vapt-keyring-exception-scope
vapt_root
vapt_package blackarch-keyring 20251001-1 "$KEYRING_SCRIPT"
archive="$SANDBOX/archives/blackarch-keyring-20251001-1-x86_64.pkg.tar.gz"
capture python3 "$VAPT_META" keyring "$archive" --root "$ROOT"
assert_status 'reviewed script accepted by keyring policy' 0 "$STATUS"
capture python3 "$VAPT_META" audit "$archive" --root "$ROOT"
assert_status 'general package audit does not inherit keyring script exemption' 1 "$STATUS"
vapt_package unrelated 1-1 "$KEYRING_SCRIPT"
capture python3 "$VAPT_META" keyring "$SANDBOX/archives/unrelated-1-1-x86_64.pkg.tar.gz" --root "$ROOT"
assert_status 'reviewed script cannot authorize another package identity' 1 "$STATUS"
printf 'depend = keyring-runtime\n' >>"$SANDBOX/packages/blackarch-keyring/.PKGINFO"
tar -czf "$archive" -C "$SANDBOX/packages/blackarch-keyring" .PKGINFO .INSTALL usr
vapt_installed 'custom-runtime|1-1|https://aur.archlinux.org/|keyring-runtime'
capture python3 "$VAPT_META" keyring "$archive" --root "$ROOT"
assert_status 'reviewed keyring script cannot exempt retained dependency provenance' 1 "$STATUS"
vapt_repos 'extra|runtime|1-1|https://example.org/runtime|keyring-runtime'
vapt_installed 'runtime|1-1|https://example.org/runtime|keyring-runtime'
capture python3 "$VAPT_META" keyring "$archive" --root "$ROOT"
assert_status 'reviewed keyring with proven available dependency accepted' 0 "$STATUS"

# --- an interrupted full upgrade blocks every package transaction ------------
guard_case() {
    vapt_sandbox "$1"
    vapt_root
    vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" "$WHOIS"
    vapt_sudo_noop
    printf 'reviewed-full-upgrade-commit-pending\n' >"$ROOT/var/lib/haseen/vapt/upgrade-pending"
}
guard_case vapt-guard-declined
vapt_api install --groups osint
assert_status "declined resume: unavailable, not failed" 0 "$STATUS"
assert_eq "declined resume: not even a transaction is solved" "" "$(vapt_calls pacman)"
assert_eq "declined resume: no privileged pacman" "" "$(vapt_calls sudo | grep -F pacman || true)"
assert_eq "declined resume: packages skipped" skipped "$(vapt_field whois 6)"
assert_eq "declined resume: native adapters skipped" skipped "$(vapt_field sherlock 6)"
assert_eq "declined resume: the record stays" yes "$([[ -e $ROOT/var/lib/haseen/vapt/upgrade-pending ]] && echo yes || echo no)"
assert_contains 'declined resume reports the incomplete upgrade, not usable source' \
    "$(grep -F $'# source\t' <<<"$OUTPUT" || true)" upgrade
vapt_tools_untouched "declined resume"

guard_case vapt-guard-failed
vapt_api install --yes --groups osint
sudo_log="$(vapt_calls sudo)"
assert_contains "accepted resume: the full upgrade is downloaded first (control)" "$sudo_log" "-Syuw"
assert_eq "failed resume: no archive opened by any commit" '' "$(vapt_calls commit-digests)"
assert_eq "failed resume: no single-package transaction is solved" 0 "$(vapt_count "$(vapt_calls pacman)" ' -Sp ')"
assert_eq "failed resume: packages skipped" skipped "$(vapt_field whois 6)"
assert_contains "failed resume: the report says the upgrade is incomplete" \
    "$(grep -F $'# source\t' <<<"$OUTPUT" || true)" "upgrade"
vapt_tools_untouched "failed resume"

# A pending upgrade also blocks bootstrap when BlackArch is not configured.
# Declining recovery may still activate passive PATH, but cannot touch trust,
# contact upstream, solve a package transaction or discard the pending marker.
guard_case vapt-guard-no-blackarch
printf '[options]\nArchitecture = auto\nSigLevel = Required DatabaseOptional\n\n[core]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n\n[extra]\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n' \
    >"$ROOT/etc/pacman.conf"
conf_before="$(cat "$ROOT/etc/pacman.conf")"
vapt_api install --groups osint
assert_status 'declined upgrade without BlackArch remains unavailable, not failed' 0 "$STATUS"
assert_contains 'blocked absent BlackArch preserves upgrade diagnostic' \
    "$(grep -F $'# source\t' <<<"$OUTPUT" || true)" upgrade
assert_eq 'blocked absent BlackArch never downloads bootstrap artifacts' '' "$(vapt_calls curl)"
assert_eq 'blocked absent BlackArch never invokes signature/key commands' '' "$(vapt_calls gpg)$(vapt_calls pacman-key)"
assert_eq 'blocked absent BlackArch never solves a transaction' '' "$(vapt_calls pacman)"
assert_eq 'blocked absent BlackArch leaves repository config unchanged' "$conf_before" "$(cat "$ROOT/etc/pacman.conf")"
assert_eq 'blocked absent BlackArch retains pending recovery evidence' yes "$([[ -e $ROOT/var/lib/haseen/vapt/upgrade-pending ]] && echo yes || echo no)"
vapt_tools_untouched 'declined upgrade without BlackArch'

guard_case vapt-guard-plan
vapt_plan "pending upgrade" --groups osint
assert_eq "the plan reviews the full upgrade before any install" yes \
    "$(awk '/^DRYRUN: sudo .*env .*pacman .* -Sy+u$/ && !u { u = NR } / -U -- / && !s { s = NR } END { print (u && s && u < s) ? "yes" : "no" }' <<<"$OUTPUT")"

# --- the pacman configuration transactions run with ----------------------------
vapt_sandbox vapt-config
vapt_root
printf '%s\n' '[options]' 'Architecture = auto' 'XferCommand = /usr/bin/curl -o %o %u' \
    'DBPath = /tmp/vapt-evil-db' 'CacheDir = /tmp/vapt-evil-cache' 'SigLevel = Never' \
    'LocalFileSigLevel = Never' '' '[core]' 'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' \
    '' '[omarchy]' 'Server = https://pkgs.omarchy.org/$arch' '' '[extra]' 'SigLevel = PackageRequired' \
    'Server = https://geo.mirror.pkgbuild.com/$repo/os/$arch' >"$ROOT/etc/pacman.conf"
capture python3 "$VAPT_META" config --root "$ROOT"
assert_status "transaction config renders" 0 "$STATUS"
config_out="$OUTPUT"
assert_contains "allowlisted repositories kept" "$config_out" "[extra]"
for bad in XferCommand /tmp/vapt-evil "SigLevel = Never" "LocalFileSigLevel = Never" "[omarchy]" omarchy.org; do
    assert_not_contains "transaction config drops: $bad" "$config_out" "$bad"
done
assert_contains "signatures are required" "$config_out" "SigLevel = Required"
printf '[options]\n[extra]\nSigLevel = Optional TrustAll\nServer = https://geo.mirror.pkgbuild.com/$repo/os/$arch\n' >"$ROOT/etc/pacman.conf"
capture python3 "$VAPT_META" config --root "$ROOT"
assert_status "a TrustAll repository refuses the configuration" 1 "$STATUS"
printf '[options]\n[extra]\nServer = http://mirror.example/$repo/os/$arch\n' >"$ROOT/etc/pacman.conf"
capture python3 "$VAPT_META" config --root "$ROOT"
assert_status "a plain-HTTP mirror refuses the configuration" 1 "$STATUS"

# --- the solver's plan must be the inspected closure ------------------------
vapt_sandbox vapt-plan-closure
vapt_root
vapt_conf_add $'[omarchy]\nServer = https://pkgs.omarchy.org/$arch'
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" "$WHOIS" "omarchy|omarchy-hooks|1-1|https://omarchy.org/"
solver_plan() { # ROW... — the pacman -Sp rows the closure check receives
    printf '%s\n' "$@" >"$SANDBOX/transaction.tsv"
    capture python3 "$VAPT_META" closure extra/whois "$SANDBOX/transaction.tsv" --root "$ROOT"
}
WHOIS_ROW=$'extra\twhois\t5.6.4-1\thttps://geo.mirror.pkgbuild.com/extra/os/x86_64/whois-5.6.4-1-x86_64.pkg.tar.zst'
solver_plan "$WHOIS_ROW"
assert_status "the inspected plan is accepted (control)" 0 "$STATUS"
solver_plan "${WHOIS_ROW//5.6.4-1/5.6.5-1}"
assert_status "a plan that differs from the inspected metadata is refused" 1 "$STATUS"
solver_plan "$WHOIS_ROW" $'omarchy\tomarchy-hooks\t1-1\thttps://pkgs.omarchy.org/x86_64/omarchy-hooks-1-1-any.pkg.tar.zst'
assert_status "a plan pulling from a non-allowlisted repository is refused" 1 "$STATUS"

# Retained dependency providers must be positively attributable to an allowed
# binary repository. Their old scriptlets are NOT rerun in this transaction.
vapt_repos "${VAPT_BASE[@]}" "$VAPT_BA_KEYRING" \
    "extra|whois|5.6.4-1|https://github.com/rfc1036/whois||libvirtual" \
    "extra|libprovider|1-1|https://example.org/libprovider|libvirtual"
vapt_installed 'custom-provider|1-1|https://aur.archlinux.org/|libvirtual'
solver_plan "$WHOIS_ROW"
assert_status 'retained AUR-only provider rejected' 1 "$STATUS"
vapt_installed 'libprovider|1-1|https://example.org/libprovider|libvirtual'
solver_plan "$WHOIS_ROW"
assert_status 'allowed retained provider accepted' 0 "$STATUS"
vapt_installed 'libprovider|2-1|https://example.org/libprovider|libvirtual'
solver_plan "$WHOIS_ROW"
assert_status 'retained provider unreviewed version rejected' 1 "$STATUS"
vapt_installed 'libprovider|1-1|https://example.org/custom-source|libvirtual'
solver_plan "$WHOIS_ROW"
assert_status 'retained provider different upstream rejected' 1 "$STATUS"
vapt_installed 'libprovider|1-1|https://example.org/libprovider|libvirtual||post_install() { systemctl enable old.service; }'
solver_plan "$WHOIS_ROW"
assert_status 'unchanged provider saved scriptlet does not run' 0 "$STATUS"
vapt_installed 'libprovider|1-1|https://example.org/libprovider|libvirtual|omarchy-hooks'
solver_plan "$WHOIS_ROW"
assert_status 'retained allowed provider cannot hide Omarchy dependency' 1 "$STATUS"

# A repository can exist and still be unsafe. Mirrors are runtime dependencies.
vapt_root
printf '[options]\n[extra]\nServer = https://stable-mirror.omarchy.org/$repo/os/$arch\n' >"$ROOT/etc/pacman.conf"
capture python3 "$VAPT_META" config --root "$ROOT"
assert_status 'Omarchy mirror refused as hidden dependency' 1 "$STATUS"

# --- downloaded archives and host hooks are audited before install ----------
if command -v bsdtar >/dev/null 2>&1; then
    vapt_sandbox vapt-audit
    vapt_root
    # pkg NAME — package archive from the tree $SANDBOX/p/NAME (makepkg-style
    # member names: .PKGINFO, .INSTALL and top-level directories, no ./).
    pkg() {
        local dir="$SANDBOX/p/$1"
        # shellcheck disable=SC2046  # one member per word
        tar -czf "$SANDBOX/$1-1-1-x86_64.pkg.tar.gz" -C "$dir" $(ls -A "$dir")
        printf '%s\n' "$SANDBOX/$1-1-1-x86_64.pkg.tar.gz"
    }
    tree() { # NAME — a minimal package tree for NAME
        mkdir -p "$SANDBOX/p/$1/usr/bin"
        printf 'pkgname = %s\npkgver = 1-1\n' "$1" >"$SANDBOX/p/$1/.PKGINFO"
        printf '#!/bin/sh\nexit 97\n' >"$SANDBOX/p/$1/usr/bin/$1"
    }
    audit() { capture python3 "$VAPT_META" audit "$@" --root "$ROOT"; }

    tree whois
    audit "$(pkg whois)"
    assert_status "a plain package passes the audit (control)" 0 "$STATUS"

    tree evil-install
    printf 'post_install() {\n    systemctl enable --now evil.service\n}\n' >"$SANDBOX/p/evil-install/.INSTALL"
    audit "$(pkg evil-install)"
    assert_status "an install scriptlet enabling a service is refused" 1 "$STATUS"

    tree evil-hook
    mkdir -p "$SANDBOX/p/evil-hook/usr/share/libalpm/hooks"
    printf '[Trigger]\nOperation = Install\nType = Package\nTarget = *\n\n[Action]\nWhen = PostTransaction\nExec = /usr/bin/systemctl enable evil.service\n' \
        >"$SANDBOX/p/evil-hook/usr/share/libalpm/hooks/evil.hook"
    audit "$(pkg evil-hook)"
    assert_status "a shipped hook enabling a service is refused" 1 "$STATUS"

    tree evil-wants
    mkdir -p "$SANDBOX/p/evil-wants/etc/systemd/system/multi-user.target.wants" "$SANDBOX/p/evil-wants/usr/lib/systemd/system"
    printf '[Service]\nExecStart=/usr/bin/evil-wants\n' >"$SANDBOX/p/evil-wants/usr/lib/systemd/system/evil.service"
    ln -s /usr/lib/systemd/system/evil.service "$SANDBOX/p/evil-wants/etc/systemd/system/multi-user.target.wants/evil.service"
    audit "$(pkg evil-wants)"
    assert_status "a package shipping an enabled unit (.wants link) is refused" 1 "$STATUS"

    mkdir -p "$ROOT/usr/share/libalpm/hooks"
    printf '[Trigger]\nOperation = Install\nType = Package\nTarget = linux\n\n[Action]\nWhen = PostTransaction\nExec = /usr/bin/omarchy-refresh-limine\n' \
        >"$ROOT/usr/share/libalpm/hooks/90-omarchy-kernel.hook"
    audit "$(pkg whois)"
    assert_status "an unrelated host hook does not block (control)" 0 "$STATUS"
    printf '[Trigger]\nOperation = Install\nOperation = Upgrade\nType = Package\nTarget = *\n\n[Action]\nWhen = PostTransaction\nExec = /usr/bin/omarchy-refresh-config\n' \
        >"$ROOT/usr/share/libalpm/hooks/91-omarchy-all.hook"
    audit "$(pkg whois)"
    assert_status "a host Omarchy hook the transaction would trigger is refused" 1 "$STATUS"
    vapt_tools_untouched "audit"

    # Operation and trigger filters distinguish installs from real upgrades.
    rm "$ROOT/usr/share/libalpm/hooks/90-omarchy-kernel.hook" "$ROOT/usr/share/libalpm/hooks/91-omarchy-all.hook"
    hook="$ROOT/usr/share/libalpm/hooks/operation.hook"
    host_hook() {
        printf '[Trigger]\nOperation = %s\nType = %s\nTarget = %s\n%s\n[Action]\nWhen = PostTransaction\nExec = %s\n' \
            "$1" "$2" "$3" "${5:-}" "$4" >"$hook"
    }
    host_hook Upgrade Package '*' '/usr/bin/systemctl enable evil.service'
    audit "$(pkg whois)"
    assert_status 'upgrade-only host hook not triggered by fresh install' 0 "$STATUS"
    vapt_installed 'whois|0-1|https://example.org/'
    audit "$(pkg whois)"
    assert_status 'same hook blocks actual upgrade' 1 "$STATUS"
    vapt_installed
    host_hook Remove Package '*' '/usr/bin/systemctl enable evil.service'
    audit "$(pkg whois)"
    assert_status 'remove-only hook not triggered by provisioning' 0 "$STATUS"
    host_hook Install Package '*' '/usr/bin/systemctl enable evil.service' 'Target = !whois'
    audit "$(pkg whois)"
    assert_status 'negative package trigger takes precedence' 0 "$STATUS"
    host_hook Install Path 'usr/bin/whois' '/usr/bin/systemctl enable evil.service'
    audit "$(pkg whois)"
    assert_status 'matching file/path trigger blocks activation' 1 "$STATUS"
    rm "$hook"

    # Delegated helpers, including interpreter payloads, must be inspected.
    # Package scriptlets run through the base-proven /bin/sh: seed the stock
    # owners (bash and its libraries, base-signed references), not hooks.
    vapt_stock
    rm -f "$ROOT"/usr/share/libalpm/hooks/*.hook
    tree delegated
    mkdir -p "$SANDBOX/p/delegated/usr/lib/delegated"
    printf 'post_install() {\n /usr/lib/delegated/setup\n}\n' >"$SANDBOX/p/delegated/.INSTALL"
    printf '#!/bin/sh\nsystemctl enable --now delegated.socket\n' >"$SANDBOX/p/delegated/usr/lib/delegated/setup"
    audit "$(pkg delegated)"
    assert_status 'packaged scriptlet helper activation rejected' 1 "$STATUS"
    printf '#!/bin/sh\nexit 0\n' >"$SANDBOX/p/delegated/usr/lib/delegated/setup"
    audit "$(pkg delegated)"
    assert_status 'inspected inert helper accepted' 0 "$STATUS"
    printf '#!/usr/bin/python3\nprint(\"nothing\")\n' >"$SANDBOX/p/delegated/usr/lib/delegated/setup"
    audit "$(pkg delegated)"
    assert_status 'opaque interpreter helper fails closed without execution' 1 "$STATUS"
    printf 'post_install() {\n echo \"run systemctl start delegated.socket\"\n}\n' >"$SANDBOX/p/delegated/.INSTALL"
    audit "$(pkg delegated)"
    assert_status 'printed service advice is not activation' 0 "$STATUS"
    printf 'post_remove() {\n systemctl start delegated.socket\n}\npost_install() {\n exit 0\n}\n' >"$SANDBOX/p/delegated/.INSTALL"
    audit "$(pkg delegated)"
    assert_status 'inactive remove scriptlet ignored for fresh install' 0 "$STATUS"
    printf 'post_upgrade() {\n systemctl start delegated.socket\n}\npost_install() {\n exit 0\n}\n' >"$SANDBOX/p/delegated/.INSTALL"
    audit "$(pkg delegated)"
    assert_status 'inactive upgrade phase ignored for fresh install' 0 "$STATUS"
    vapt_installed 'delegated|0-1|https://example.org/'
    audit "$(pkg delegated)"
    assert_status 'active upgrade phase rejected' 1 "$STATUS"
    # Back to the stock local DB: no delegated package installed.
    rm -f "$ROOT/var/lib/haseen/vapt/installed.json"
    printf 'post_install() {\n echo \"$(systemctl start delegated.socket)\"\n}\n' >"$SANDBOX/p/delegated/.INSTALL"
    audit "$(pkg delegated)"
    assert_status 'echo substitution cannot hide activation' 1 "$STATUS"

    mkdir -p "$ROOT/usr/local/lib"
    printf '#!/bin/sh\nsystemctl enable --now helper.socket\n' >"$ROOT/usr/local/lib/setup"
    host_hook Install Package whois '/bin/sh /usr/local/lib/setup'
    audit "$(pkg whois)"
    assert_status 'host hook interpreter payload audited' 1 "$STATUS"
    printf '#!/bin/sh\nexit 0\n' >"$ROOT/usr/local/lib/setup"
    audit "$(pkg whois)"
    assert_status 'host interpreter inert payload control' 0 "$STATUS"
    host_hook Install Package whois '/bin/sh -c true'
    audit "$(pkg whois)"
    assert_status 'dynamic interpreter invocation fails closed' 1 "$STATUS"
    rm "$hook"

    tree incoming
    mkdir -p "$SANDBOX/p/incoming/usr/share/libalpm/hooks" "$SANDBOX/p/incoming/usr/lib/incoming"
    printf '[Trigger]\nOperation = Install\nType = Package\nTarget = incoming\n[Action]\nWhen = PostTransaction\nExec = /usr/lib/incoming/setup\n' \
        >"$SANDBOX/p/incoming/usr/share/libalpm/hooks/setup.hook"
    printf '#!/bin/sh\nsystemctl start incoming.socket\n' >"$SANDBOX/p/incoming/usr/lib/incoming/setup"
    audit "$(pkg incoming)"
    assert_status 'incoming hook and new helper audited together' 1 "$STATUS"
    printf '#!/bin/sh\nexit 0\n' >"$SANDBOX/p/incoming/usr/lib/incoming/setup"
    audit "$(pkg incoming)"
    assert_status 'incoming inert hook/helper control' 0 "$STATUS"

    # Pacman /etc hooks override the same basename from /usr/share, even
    # when that lower-priority hook is introduced by the incoming archive.
    mkdir -p "$ROOT/etc/pacman.d/hooks"
    ln -s /dev/null "$ROOT/etc/pacman.d/hooks/setup.hook"
    printf '#!/bin/sh\nsystemctl start incoming.socket\n' >"$SANDBOX/p/incoming/usr/lib/incoming/setup"
    audit "$(pkg incoming)"
    assert_status 'explicit /etc hook mask wins over incoming /usr hook' 0 "$STATUS"
    vapt_tools_untouched 'delegated payload audit'
else
    echo "  (note: bsdtar is not installed; the archive audit was skipped)"
fi
