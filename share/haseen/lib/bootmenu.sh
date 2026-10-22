# shellcheck shell=bash disable=SC2034  # BOOTMENU_* are read by the command and the helper
# bootmenu.sh — Limine's menu wait: the `timeout:` and `quiet:` lines of
# limine.conf's header (plan 104). Sourced by bin/haseen-setup-boot-menu and
# by lib/limine-header.sh, which writes the file as root.
#
# Omarchy 4.5 boots through Limine's menu in a second: `timeout: 1` and
# `quiet: yes` (3b4c5d0da, #15301; default/limine/limine.conf@v4.5.0-rc1:2-3),
# and with `quiet: yes` a key pressed during that second shows the menu
# (/usr/share/doc/limine/CONFIG.md, `quiet`, limine 12.9.3). limine-entry-tool
# has no key for either (limine-mkinitcpio-hook 1.40.0: its strings carry only
# the `timeout: 3` / `#quiet: yes` header it writes into a new limine.conf), so
# the header has to be edited in place, which haseen otherwise never does
# (architecture §3). The rules that keep that safe live here:
#   - only a layout haseen understands is edited (bootmenu_problems): menu
#     entries present, and at most one uncommented `timeout:` and `quiet:`,
#     both above the first entry, with values Limine documents;
#   - only those two lines change, nothing else in the file;
#   - the values haseen replaced are recorded once, and `normal` puts them
#     back; the whole file is copied to BOOTMENU_DIR before every write.

[[ -n ${HASEEN_BOOTMENU_SH:-} ]] && return 0
HASEEN_BOOTMENU_SH=1

# shellcheck source=common.sh
source "$(dirname "${BASH_SOURCE[0]}")/common.sh"

# Root-owned state: backups and the record of what `fast` replaced.
BOOTMENU_DIR="$HASEEN_STATE_DIR/boot-menu"
BOOTMENU_RECORD="$BOOTMENU_DIR/original"
# limine-entry-tool and limine-snapper-sync take this lock (flock) before they
# change files on the ESP (/usr/lib/limine/limine-mutex, BOOT_PARTITION_LOCK).
BOOTMENU_LOCK=/run/lock/boot-partition.lock
# The fast values, and the "absent" marker for a key the file did not have.
BOOTMENU_FAST_TIMEOUT=1
BOOTMENU_FAST_QUIET=yes
BOOTMENU_ABSENT=-

# bootmenu_key_line KEY FILE — line numbers of every uncommented KEY: option
# (Limine option names are case-insensitive), one per line.
bootmenu_key_line() {
    awk -v key="$1" 'tolower($0) ~ ("^[[:space:]]*" key ":") { print NR }' "$2"
}

# bootmenu_value KEY FILE — KEY's value, or BOOTMENU_ABSENT when the file has
# no uncommented KEY: line.
bootmenu_value() {
    local v
    v="$(awk -v key="$1" '
        tolower($0) ~ ("^[[:space:]]*" key ":") {
            sub(/^[^:]*:[[:space:]]*/, ""); sub(/[[:space:]]+$/, ""); print; exit
        }' "$2")"
    printf '%s\n' "${v:-$BOOTMENU_ABSENT}"
}

# bootmenu_problems FILE — why FILE is not a limine.conf whose menu wait
# haseen can change, one reason per line; nothing when it is.
bootmenu_problems() {
    local f="$1" first key lines n v
    if [[ ! -f $f || -L $f ]]; then
        echo "$f is not a regular file"
        return 0
    fi
    if [[ ! -r $f ]]; then
        echo "$f is not readable"
        return 0
    fi
    if ! tr -d '\000\r' <"$f" | cmp -s - "$f"; then
        echo "it contains NUL or carriage-return bytes"
    fi
    first="$(awk '/^[[:space:]]*\// { print NR; exit }' "$f")"
    if [[ -z $first ]]; then
        echo "it has no menu entry (no line starting with /)"
        first=999999999
    fi
    for key in timeout quiet; do
        lines="$(bootmenu_key_line "$key" "$f")"
        [[ -n $lines ]] || continue
        if (($(wc -l <<<"$lines") > 1)); then
            echo "it sets $key: more than once (lines $(tr '\n' ' ' <<<"$lines" | sed 's/ $//'))"
            continue
        fi
        n="$lines"
        ((n < first)) || echo "its $key: (line $n) is not in the header above the first entry"
        v="$(bootmenu_value "$key" "$f")"
        if [[ $v == "$BOOTMENU_ABSENT" ]] || ! bootmenu_valid "$key" "$v"; then
            echo "its $key: value '$v' is not one Limine documents"
        fi
    done
    return 0
}

# bootmenu_render FILE TIMEOUT QUIET — FILE with its header's timeout: and
# quiet: set to TIMEOUT and QUIET, on stdout. BOOTMENU_ABSENT removes the
# line. A missing timeout: goes on the first line, a missing quiet: right
# after timeout: (or first, without one). Every other line is copied as is.
# FILE must pass bootmenu_problems.
bootmenu_render() {
    local f="$1" t="$2" q="$3" ht=0 hq=0
    [[ -n $(bootmenu_key_line timeout "$f") ]] && ht=1
    [[ -n $(bootmenu_key_line quiet "$f") ]] && hq=1
    awk -v t="$t" -v q="$q" -v ht="$ht" -v hq="$hq" -v absent="$BOOTMENU_ABSENT" '
        BEGIN { tl = (t == absent) ? "" : "timeout: " t; ql = (q == absent) ? "" : "quiet: " q }
        NR == 1 {
            if (!ht && tl != "") print tl
            if (!hq && ql != "" && !(ht && tl != "")) { print ql; qdone = 1 }
        }
        tolower($0) ~ /^[[:space:]]*timeout:/ {
            if (tl != "") {
                print tl
                if (!hq && ql != "" && !qdone) { print ql; qdone = 1 }
            }
            next
        }
        tolower($0) ~ /^[[:space:]]*quiet:/ { if (ql != "") print ql; next }
        { print }
    ' "$f"
}

# bootmenu_mode TIMEOUT QUIET — "fast" for haseen's values, else "normal".
bootmenu_mode() {
    if [[ $1 == "$BOOTMENU_FAST_TIMEOUT" && $2 == "$BOOTMENU_FAST_QUIET" ]]; then
        echo fast
    else
        echo normal
    fi
}

# bootmenu_record_value KEY — the value `fast` replaced, from the record;
# fails when there is no record (or no such key in it).
bootmenu_record_value() {
    local f line
    f="$(sysroot_path "$BOOTMENU_RECORD")"
    [[ -r $f ]] || return 1
    line="$(grep -m1 "^$1=" "$f")" || return 1
    printf '%s\n' "${line#*=}"
}

# bootmenu_valid KEY VALUE — VALUE is one haseen writes for KEY.
bootmenu_valid() {
    case "$1" in
    timeout) [[ $2 =~ ^(no|[0-9]+(\.[0-9]+)?)$ || $2 == "$BOOTMENU_ABSENT" ]] ;;
    quiet) [[ $2 =~ ^(yes|no)$ || $2 == "$BOOTMENU_ABSENT" ]] ;;
    *) return 1 ;;
    esac
}

# bootmenu_describe KEY VALUE — a value as Limine reads it.
bootmenu_describe() {
    case "$1:$2" in
    "timeout:$BOOTMENU_ABSENT") echo "not set (Limine waits 5 s)" ;;
    timeout:no) echo "no (Limine waits for a choice)" ;;
    timeout:0) echo "0 (Limine boots at once, no menu)" ;;
    timeout:*) echo "$2 s" ;;
    "quiet:$BOOTMENU_ABSENT") echo "not set (the menu shows)" ;;
    quiet:yes) echo "yes (the menu shows only when a key is pressed)" ;;
    quiet:no) echo "no (the menu shows)" ;;
    esac
}
