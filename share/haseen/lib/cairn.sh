# shellcheck shell=bash
# cairn.sh — Cairn, the owner's backup extension, in the Helium browser
# (plan 073). Sourced, never executed.
#
# Cairn (github.com/t1nk333r/cairn, AGPL-3.0) is not shipped with haseen: the
# signed .crx of a release is downloaded at install time, checked against a
# SHA-256 and against the extension ID its key proves, and handed to Helium
# through Chromium's per-user external extensions directory:
#
#   ~/.config/net.imput.helium/External Extensions/<id>.json
#   {"external_crx": "<absolute path of the .crx>", "external_version": "<version>"}
#
# Helium installs it on its next start, enabled, without developer mode, and
# updates it whenever external_version rises. No root is needed and Chromium,
# which shares /usr/share/chromium/extensions and /etc/chromium/policies with
# Helium, is left out. Deleting the file would make Helium uninstall Cairn and
# its settings (an orphaned external extension), so haseen never deletes it.
# A user who removes Cairn in Helium keeps it removed: Helium records that.

[[ -n ${HASEEN_CAIRN_SH:-} ]] && return 0
HASEEN_CAIRN_SH=1
# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# The release the shell layer installs, its .crx's SHA-256 and the ID of the
# maintainer's signing key (the crx_id in the signed header, which the RSA key
# hashes to). `haseen setup cairn update` moves past the pin.
CAIRN_VERSION=${HASEEN_CAIRN_VERSION:-0.1.1}
CAIRN_SHA256=${HASEEN_CAIRN_SHA256:-030d8b3c30c6a739c935ae4ef0815ba72e5efc3cbc887ae8368cebbc6365d6f7}
CAIRN_ID=${HASEEN_CAIRN_ID:-bddeidknhkokohcgdkpgdmlppgfkblig}

CAIRN_RELEASES=https://github.com/t1nk333r/cairn/releases
CAIRN_LATEST_API=https://api.github.com/repos/t1nk333r/cairn/releases/latest
CAIRN_MAX_BYTES=10485760
CAIRN_DIR="${XDG_DATA_HOME:-$HOME/.local/share}/haseen/extensions/cairn"
# Helium's user data directory (the binary's "net.imput.helium"); Chromium
# reads "External Extensions" next to the profiles, so every profile gets it.
HELIUM_USER_DATA="${XDG_CONFIG_HOME:-$HOME/.config}/net.imput.helium"
CAIRN_EXTERNAL_JSON="$HELIUM_USER_DATA/External Extensions/$CAIRN_ID.json"

cairn_crx() { printf '%s/%s/cairn-%s.crx\n' "$CAIRN_DIR" "$1" "$1"; }

cairn_sha256() { sha256sum -- "$1" | cut -d' ' -f1; }

# cairn_version_gt A B — A is a later version than B.
cairn_version_gt() {
    [[ $1 != "$2" && $(printf '%s\n%s\n' "$1" "$2" | sort -V | tail -n1) == "$1" ]]
}

# --- the ID a CRX3 file proves ---------------------------------------------
# A CRX3 file is "Cr24", version 3 and a header length (little-endian
# uint32s), then a protobuf CrxFileHeader: AsymmetricKeyProofs in fields 2
# (RSA) and 3 (ECDSA), each with its public_key in field 1, and the signed
# header data in field 10000, whose field 1 is the 16-byte crx_id. Chromium
# derives an extension's ID from the SHA-256 of its key: the first 16 bytes
# in hex, 0-f spelt a-p. Helium verifies the signatures when it installs;
# this check makes sure the file is Cairn before haseen points Helium at it.

# _crx_varint — read a varint at P in H; sets V, advances P.
_crx_varint() {
    local c s=0
    V=0
    while :; do
        ((P < ${#H[@]} && s < 35)) || return 1
        c=${H[P]}
        P=$((P + 1))
        V=$((V | ((c & 127) << s)))
        s=$((s + 7))
        ((c < 128)) && return 0
    done
}

# _crx_fields START END — the length-delimited fields of H[START..END), one
# "field offset length" line each; varints are skipped, other types refused.
_crx_fields() {
    local P="$1" end="$2" V field len
    while ((P < end)); do
        _crx_varint || return 1
        field=$((V >> 3))
        case $((V & 7)) in
        0) _crx_varint || return 1 ;;
        2)
            _crx_varint || return 1
            len=$V
            ((P + len <= end)) || return 1
            printf '%s %s %s\n' "$field" "$P" "$len"
            P=$((P + len))
            ;;
        *) return 1 ;;
        esac
    done
}

# cairn_crx_id FILE — the extension ID FILE is signed for, printed only when
# one of its keys hashes to the crx_id of its signed header.
cairn_crx_id() {
    local file="$1" hdr=() H=() n field off len sfield soff slen want="" i hex
    local keys=()
    [[ -f $file && $(head -c 4 -- "$file") == Cr24 ]] || return 1
    read -r -a hdr <<<"$(od -An -tu1 -v -j 4 -N 8 -- "$file" | tr '\n' ' ')"
    ((${#hdr[@]} == 8)) || return 1
    ((hdr[0] == 3 && hdr[1] == 0 && hdr[2] == 0 && hdr[3] == 0)) || return 1
    n=$((hdr[4] | hdr[5] << 8 | hdr[6] << 16 | hdr[7] << 24))
    ((n > 0 && n <= 65536)) || return 1
    read -r -a H <<<"$(od -An -tu1 -v -j 12 -N "$n" -- "$file" | tr '\n' ' ')"
    ((${#H[@]} == n)) || return 1
    while read -r field off len; do
        case "$field" in
        2 | 3)
            while read -r sfield soff slen; do
                [[ $sfield == 1 ]] && keys+=("$soff $slen")
            done < <(_crx_fields "$off" $((off + len)))
            ;;
        10000)
            while read -r sfield soff slen; do
                [[ $sfield == 1 && $slen == 16 ]] || continue
                want=""
                for ((i = soff; i < soff + 16; i++)); do want+="$(printf '%02x' "${H[i]}")"; done
            done < <(_crx_fields "$off" $((off + len)))
            ;;
        esac
    done < <(_crx_fields 0 "$n")
    [[ -n $want ]] || return 1
    for i in "${keys[@]}"; do
        read -r off len <<<"$i"
        hex="$(tail -c +$((12 + off + 1)) -- "$file" | head -c "$len" | sha256sum | cut -c1-32)"
        if [[ $hex == "$want" ]]; then
            tr '0-9a-f' 'a-p' <<<"$hex"
            return 0
        fi
    done
    return 1
}

# --- deploy ----------------------------------------------------------------

# cairn_deployed_version — the version the external extensions file names.
cairn_deployed_version() {
    [[ -r $CAIRN_EXTERNAL_JSON ]] || return 0
    jq -r '.external_version // empty | strings' "$CAIRN_EXTERNAL_JSON" 2>/dev/null || true
}

cairn_external_json() {
    jq -n --arg crx "$(cairn_crx "$1")" --arg v "$1" '{external_crx: $crx, external_version: $v}'
}

# cairn_fetch VERSION SHA256 — put cairn-VERSION.crx in its version directory.
# The download lands in a hidden .part file and moves into place only after
# its SHA-256 and the ID its key proves both match; otherwise it is deleted.
cairn_fetch() {
    local version="$1" sha="$2" crx dir part url got id status=0
    crx="$(cairn_crx "$version")"
    if [[ -f $crx && $(cairn_sha256 "$crx") == "$sha" ]]; then
        return 0
    fi
    dir="$(dirname "$crx")"
    part="$dir/.cairn-$version.crx.part"
    url="$CAIRN_RELEASES/download/v$version/cairn-$version.crx"
    $DRY_RUN || require_cmds curl sha256sum od
    run mkdir -p -- "$dir"
    run curl --fail --silent --show-error --location --proto =https --proto-redir =https \
        --max-filesize "$CAIRN_MAX_BYTES" --connect-timeout 20 --retry 3 \
        --output "$part" -- "$url" || status=$?
    if $DRY_RUN; then
        echo "then: the .crx must have sha256 $sha and be signed for $CAIRN_ID, else it is deleted"
        return 0
    fi
    if ((status != 0)); then
        rm -f -- "$part"
        warn "cairn-$version.crx: download failed (curl exit $status)"
        return 1
    fi
    got="$(cairn_sha256 "$part")"
    if [[ $got != "$sha" ]]; then
        rm -f -- "$part"
        warn "cairn-$version.crx: sha256 $got does not match $sha; deleted"
        return 1
    fi
    id="$(cairn_crx_id "$part")" || id=""
    if [[ $id != "$CAIRN_ID" ]]; then
        rm -f -- "$part"
        warn "cairn-$version.crx is signed for ${id:-no extension ID}, not Cairn's $CAIRN_ID; deleted"
        return 1
    fi
    mv -f -- "$part" "$crx"
}

# cairn_deploy VERSION SHA256 — fetch the .crx, point Helium at it and drop
# the other versions' directories. Idempotent.
cairn_deploy() {
    local version="$1" sha="$2" want d
    cairn_fetch "$version" "$sha" || return 1
    want="$(cairn_external_json "$version")"
    if [[ -f $CAIRN_EXTERNAL_JSON && $(cat -- "$CAIRN_EXTERNAL_JSON") == "$want" ]]; then
        info "Cairn $version is already handed to Helium"
    else
        write_user_file "$CAIRN_EXTERNAL_JSON" <<<"$want"
        info "Helium installs Cairn $version on its next start"
    fi
    for d in "$CAIRN_DIR"/*/; do
        [[ -d $d && ${d%/} != "$CAIRN_DIR/$version" ]] || continue
        run rm -rf -- "${d%/}"
    done
}

# cairn_install — the pinned release, unless a later one is already deployed
# (`haseen setup cairn update`): a re-apply never downgrades.
cairn_install() {
    local have
    have="$(cairn_deployed_version)"
    if [[ -n $have ]] && cairn_version_gt "$have" "$CAIRN_VERSION"; then
        info "Cairn $have stays (newer than haseen's pinned $CAIRN_VERSION)"
        return 0
    fi
    cairn_deploy "$CAIRN_VERSION" "$CAIRN_SHA256"
}

# cairn_latest — "VERSION SHA256" of the latest release's .crx, from the
# GitHub API (GitHub computes each asset's digest). A read: it runs in a dry
# run too, so the plan names the version.
cairn_latest() {
    curl --fail --silent --show-error --location --max-time 20 \
        -H 'Accept: application/vnd.github+json' -- "$CAIRN_LATEST_API" |
        jq -r '(.tag_name // "" | ltrimstr("v")) as $v
            | [.assets[]? | select(.name == "cairn-\($v).crx")][0] // empty
            | "\($v) \(.digest // "" | ltrimstr("sha256:"))"'
}

# cairn_update — deploy the latest release.
cairn_update() {
    local latest version sha have
    latest="$(cairn_latest)" || die "cannot read the latest Cairn release ($CAIRN_LATEST_API)"
    read -r version sha <<<"$latest"
    [[ $version =~ ^[0-9]+(\.[0-9]+){0,3}$ ]] || die "the latest Cairn release has no cairn-<version>.crx asset"
    [[ $sha =~ ^[0-9a-f]{64}$ ]] || die "the latest Cairn release publishes no sha256 for cairn-$version.crx; refusing an unchecked download"
    have="$(cairn_deployed_version)"
    if [[ -n $have ]] && cairn_version_gt "$have" "$version"; then
        info "Cairn $have is newer than the latest release $version; left as is"
        return 0
    fi
    info "Cairn: latest release $version (deployed: ${have:-none})"
    cairn_deploy "$version" "$sha"
}

# cairn_status — "ok:"/"missing:" lines; 0 when Helium has Cairn or will on
# its next start, 1 otherwise. Read-only.
cairn_status() {
    local have crx prefs
    have="$(cairn_deployed_version)"
    if [[ -z $have ]]; then
        echo "missing: Cairn is not set up for Helium (haseen setup cairn)"
        return 1
    fi
    crx="$(cairn_crx "$have")"
    prefs="$HELIUM_USER_DATA/Default/Preferences"
    if [[ -r $prefs ]] && jq -e --arg id "$CAIRN_ID" '.extensions.external_uninstalls // [] | index($id)' "$prefs" >/dev/null 2>&1; then
        echo "ok: Cairn was removed in Helium; haseen leaves it removed"
    elif compgen -G "$HELIUM_USER_DATA/*/Extensions/$CAIRN_ID/*" >/dev/null; then
        echo "ok: Cairn $have in Helium"
    elif [[ -f $crx ]]; then
        echo "ok: Cairn $have handed to Helium (installed on its next start)"
    else
        echo "missing: $crx is gone before Helium installed it (haseen setup cairn)"
        return 1
    fi
}
