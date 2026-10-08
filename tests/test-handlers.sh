# shellcheck shell=bash
# Run through tests/run.sh: it sources tests/lib.sh, whose sandbox moves HOME
# off the live machine. Run directly, the fixtures land in the real ~/.config.
[[ -v TESTS_RUN ]] || { echo "run it as: tests/run.sh ${BASH_SOURCE[0]}" >&2; return 2 2>/dev/null || exit 2; }
# Default handlers: the vendor mimeapps.list and xdg-terminals.list shipped
# under PREFIX/share, the user-level xdg-mime kinds of `haseen setup default`,
# and the 50-handlers seed. Hermetic: fixture sysroot, scratch HOME, stub PATH.

SETUP="$REPO/bin/haseen-setup-default"
SEED="$REPO/share/haseen/seeds/50-handlers.sh"
MIMEAPPS="$REPO/share/haseen/default/applications/mimeapps.list"
TERMLIST="$REPO/share/haseen/default/xdg-terminal-exec/hyprland-xdg-terminals.list"

# array_body FILE OPENER — the text between "OPENER" and its closing ")",
# whether the array is written on one line or many.
array_body() {
    awk -v start="$2" '
        !inside { if (index($0, start) != 1) next; inside = 1; sub(/^[^(]*\(/, "") }
        { closed = sub(/\)[[:space:]]*$/, ""); print; if (closed) exit }
    ' "$1"
}

# setup_mimes KIND — the MIME_<kind> array from haseen-setup-default.
setup_mimes() { array_body "$SETUP" "MIME_$1=(" | tr ' ' '\n' | sed '/^$/d' | sort; }

# vendor_mimes DESKTOP — the MIME types the vendor list points at DESKTOP.
vendor_mimes() { grep -E "^[^#=]+=$1\$" "$MIMEAPPS" | cut -d= -f1 | sort; }

# map_rows FILE NAME — "[key]=value" rows of a declare -A block.
map_rows() { array_body "$1" "declare -A $2=(" | grep -oE '\[[a-z]+\]=[^] )]+' | sort; }

# --- the vendor files ---------------------------------------------------------
assert_contains "vendor list: default section" "$(cat "$MIMEAPPS")" "[Default Applications]"
assert_contains "vendor list: credits Omarchy's coverage" "$(cat "$MIMEAPPS")" "Omarchy default/applications/mimeapps.list"
assert_eq "vendor list: directories open in the file manager" "inode/directory" "$(vendor_mimes yazi.desktop)"
assert_eq "vendor list: PDFs open in papers" "application/pdf" "$(vendor_mimes org.gnome.Papers.desktop)"
assert_eq "vendor list: links open in Helium" "x-scheme-handler/http"$'\n'"x-scheme-handler/https" "$(vendor_mimes helium.desktop)"
# Every desktop id the vendor list names comes from a package a default layer
# installs, except nvim.desktop: neovim is catalogue-only, said in the header.
declare -A VENDOR_PKG=([yazi.desktop]=yazi [imv.desktop]=imv [mpv.desktop]=mpv
    [org.gnome.Papers.desktop]=papers [helium.desktop]=aur:helium-browser-bin)
default_pkgs="$(for l in base chaotic omarchy-repo desktop theme shell; do
    f="$REPO/share/haseen/layers/$l/packages.txt"
    if [[ -r $f ]]; then sed 's/#.*//' "$f" | tr -s ' \t' '\n' | sed '/^$/d'; fi
done | sort -u)"
dangling=""
while IFS= read -r id; do
    [[ $id == nvim.desktop ]] && continue
    pkg="${VENDOR_PKG[$id]:-}"
    if [[ -z $pkg ]] || ! grep -qxF -- "$pkg" <<<"$default_pkgs"; then dangling+="$id "; fi
done < <(grep -E '^[^#=]+=' "$MIMEAPPS" | cut -d= -f2 | sort -u)
assert_eq "vendor list: every app is installed by a default layer (nvim aside)" "" "$dangling"
# Omarchy's set is the proven one, so every type it covers is still covered.
omarchy_types="$(grep -oE '^[a-z-]+/[A-Za-z0-9.+-]+' /usr/share/omarchy/default/applications/mimeapps.list 2>/dev/null | sort -u || true)"
if [[ -n $omarchy_types ]]; then
    missing="$(comm -23 <(printf '%s\n' "$omarchy_types" | grep -v '^x-scheme-handler/mailto$') \
        <(grep -oE '^[a-z-]+/[A-Za-z0-9.+-]+' "$MIMEAPPS" | sort -u))"
    assert_eq "vendor list: covers every type Omarchy's does (mailto aside)" "" "$missing"
fi
assert_eq "vendor terminal list: foot" "foot.desktop" "$(grep -v '^#' "$TERMLIST" | sed '/^$/d')"
assert_contains "vendor terminal list: says why the name matters" "$(cat "$TERMLIST")" "XDG_CURRENT_DESKTOP"

# Each handler kind owns exactly the block the vendor file assigns to its app.
assert_eq "kind files matches the vendor block" "$(vendor_mimes yazi.desktop)" "$(setup_mimes files)"
assert_eq "kind image matches the vendor block" "$(vendor_mimes imv.desktop)" "$(setup_mimes image)"
assert_eq "kind video matches the vendor block" "$(vendor_mimes mpv.desktop)" "$(setup_mimes video)"
assert_eq "kind pdf matches the vendor block" "$(vendor_mimes org.gnome.Papers.desktop)" "$(setup_mimes pdf)"
assert_eq "kind text matches the vendor block" "$(vendor_mimes nvim.desktop)" "$(setup_mimes text)"
assert_contains "kind image covers what imv declares beyond Omarchy" "$(setup_mimes image)" "image/avif"
assert_contains "kind video keeps Omarchy's ogg container" "$(setup_mimes video)" "application/ogg"

# The seed and the command write the same file, so their maps must agree.
assert_eq "terminal .desktop map: seed == setup default" \
    "$(map_rows "$SETUP" TERMINAL_DESKTOPS)" "$(map_rows "$SEED" SEED_TERMINAL_DESKTOPS)"
assert_contains "terminal .desktop map: foot" "$(map_rows "$SETUP" TERMINAL_DESKTOPS)" "[foot]=foot.desktop"

# --- the installer plans both vendor files ------------------------------------
sandbox handlers-install
capture env HASEEN_SYSROOT="$FIXTURES/cachyos-grub-plain" "$REPO/install.sh" --dry-run --tree-only
assert_status "install tree dry-run" 0 "$STATUS"
assert_dry_pure "install.sh vendor files" "$OUTPUT"
assert_contains "installs the vendor mimeapps.list" "$OUTPUT" \
    "install -Dm0644 $REPO/share/haseen/default/applications/mimeapps.list /usr/local/share/applications/mimeapps.list"
assert_contains "installs the vendor terminal list" "$OUTPUT" \
    "install -Dm0644 $REPO/share/haseen/default/xdg-terminal-exec/hyprland-xdg-terminals.list /usr/local/share/xdg-terminal-exec/hyprland-xdg-terminals.list"
capture env HASEEN_SYSROOT="$FIXTURES/cachyos-grub-plain" "$REPO/install.sh" --dry-run --uninstall-tree
assert_contains "uninstall removes the vendor mimeapps.list" "$OUTPUT" \
    "rm -f /usr/local/share/applications/mimeapps.list"
assert_contains "uninstall removes the vendor terminal list" "$OUTPUT" \
    "rm -f /usr/local/share/xdg-terminal-exec/hyprland-xdg-terminals.list"

# --- the seed -----------------------------------------------------------------
sandbox handlers-seed
export HASEEN_SYSROOT="$FIXTURES/seeds-plain"
CONFIG="$HOME/.config"

capture haseen seed user --dry-run
assert_status "seed dry run succeeds" 0 "$STATUS"
assert_dry_pure "seed dry run" "$OUTPUT"
assert_contains "the terminal list is planned" "$OUTPUT" "DRYRUN: write $CONFIG/xdg-terminals.list"
assert_contains "the plan shows foot as the fallback" "$OUTPUT" "| foot.desktop"
assert_eq "the dry run wrote no terminal list" "no" "$([[ -e $CONFIG/xdg-terminals.list ]] && echo yes || echo no)"
capture haseen seed user --help
assert_contains "--help names the terminal list" "$OUTPUT" "$CONFIG/xdg-terminals.list"

# The chosen terminal wins over the default: the env file `haseen setup default
# terminal` writes is read, not sourced.
mkdir -p "$CONFIG/uwsm/env.d"
printf 'export TERMINAL=kitty\n' >"$CONFIG/uwsm/env.d/60-haseen-defaults"
capture haseen seed user
assert_status "seeding succeeds" 0 "$STATUS"
assert_eq "the seed follows the chosen terminal" "kitty.desktop" \
    "$(grep -v '^#' "$CONFIG/xdg-terminals.list" | sed '/^$/d')"
assert_contains "the seeded file says what reads it" "$(cat "$CONFIG/xdg-terminals.list")" "xdg-terminal-exec"
echo "mine.desktop" >"$CONFIG/xdg-terminals.list"
capture haseen seed user
assert_eq "an edited terminal list is never re-seeded" "mine.desktop" "$(cat "$CONFIG/xdg-terminals.list")"
capture haseen seed user --dry-run
assert_not_contains "a re-run plans no terminal list" "$OUTPUT" "xdg-terminals.list"

# --- haseen setup default: the handler kinds ----------------------------------
sandbox handlers-default
export HASEEN_SYSROOT="$SANDBOX/root"
mkdir -p "$HASEEN_SYSROOT/usr/share/applications"
: >"$HASEEN_SYSROOT/usr/share/applications/imv.desktop"
: >"$HASEEN_SYSROOT/usr/share/applications/org.gnome.Papers.desktop"
CONFIG="$HOME/.config"
all=""

capture haseen setup default --help
assert_status "--help exits 0" 0 "$STATUS"
for kind in files image video pdf text; do
    assert_contains "--help lists the $kind kind" "$OUTPUT" "  $kind"
done
assert_contains "--help shows an installed app plainly" "$OUTPUT" " imv"
assert_contains "--help marks a missing app" "$OUTPUT" "loupe(not installed)"
assert_contains "--help names the user file xdg-mime writes" "$OUTPUT" ".config/mimeapps.list"

capture haseen setup default pdf papers --dry-run
all+="$OUTPUT"
assert_status "pdf: exit" 0 "$STATUS"
assert_contains "pdf: one xdg-mime call for the whole set" "$OUTPUT" \
    "DRYRUN: xdg-mime default org.gnome.Papers.desktop application/pdf"
assert_contains "pdf: says what it chose" "$OUTPUT" "default pdf: papers (org.gnome.Papers.desktop)"

capture haseen setup default image imv --dry-run
all+="$OUTPUT"
assert_contains "image: every type in one call" "$OUTPUT" "image/png image/x-png image/jpeg"
assert_contains "image: the widened set" "$OUTPUT" "image/jxl"
capture haseen setup default files flea --dry-run
all+="$OUTPUT"
assert_contains "files: flea by desktop id" "$OUTPUT" "DRYRUN: xdg-mime default com.thisisgm.flea.desktop inode/directory"
# A dry run prints no "not installed" warning by convention; the real run does.
capture haseen setup default video mpv --dry-run
all+="$OUTPUT"
assert_contains "video: application/ogg goes to the player too" "$OUTPUT" "application/ogg"
capture haseen setup default text nvim --dry-run
all+="$OUTPUT"
assert_contains "text: source types too" "$OUTPUT" "text/x-csrc"
assert_dry_pure "setup default handlers" "$all"
assert_eq "the handler dry runs wrote nothing" "" "$(find "$HOME" -type f -o -type l | sort | tr '\n' ' ')"

capture haseen setup default pdf no-such-viewer --dry-run
assert_status "pdf: unknown name refused" 1 "$STATUS"
assert_contains "pdf: unknown name message" "$OUTPUT" "unknown pdf 'no-such-viewer'"
capture haseen setup default nosuchkind
assert_status "unknown kind is a usage error" 2 "$STATUS"

# Queries read xdg-mime and translate the .desktop back to a name.
stub xdg-mime 'if [ "$1" = query ]; then echo imv.desktop; else echo "STUB-CALLED: xdg-mime $*" >&2; exit 97; fi'
capture haseen setup default image
assert_eq "image: current default by name" "imv" "$OUTPUT"
stub xdg-mime 'if [ "$1" = query ]; then echo org.kde.gwenview.desktop; else exit 97; fi'
capture haseen setup default image
assert_eq "image: an app haseen does not list prints raw" "org.kde.gwenview.desktop" "$OUTPUT"
stub xdg-mime 'exit 0'
capture haseen setup default files flea
assert_status "files: a real run succeeds" 0 "$STATUS"
assert_contains "files: warns when the app is not installed yet" "$OUTPUT" \
    "com.thisisgm.flea.desktop is not installed yet"

# --- terminal and editor carry their handler half -----------------------------
stub xdg-mime 'echo "STUB-CALLED: xdg-mime $*" >&2; exit 97'
capture haseen setup default terminal kitty --dry-run
assert_dry_pure "terminal dry run" "$OUTPUT"
assert_contains "terminal: still writes the env file" "$OUTPUT" "export TERMINAL=kitty"
assert_contains "terminal: also plans the xdg-terminals.list" "$OUTPUT" "DRYRUN: write $CONFIG/xdg-terminals.list"
assert_contains "terminal: with kitty's desktop id" "$OUTPUT" "| kitty.desktop"

: >"$HASEEN_SYSROOT/usr/share/applications/nvim.desktop"
capture haseen setup default editor nvim --dry-run
assert_dry_pure "editor dry run" "$OUTPUT"
assert_contains "editor: still writes the env file" "$OUTPUT" "export EDITOR=nvim"
assert_contains "editor: also sets the text handlers" "$OUTPUT" "DRYRUN: xdg-mime default nvim.desktop text/plain"
capture haseen setup default editor zed --dry-run
assert_contains "editor: no desktop entry, no MIME change" "$OUTPUT" "is not installed, so the text/* handlers are unchanged"
assert_not_contains "editor: and xdg-mime is not called" "$OUTPUT" "xdg-mime default dev.zed.Zed.desktop"
capture haseen setup default agent claude --dry-run
assert_not_contains "agent: unaffected by handlers" "$OUTPUT" "xdg-mime"
