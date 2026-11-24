# shellcheck shell=bash
# Plan 190: `haseen setup keyd on` wrote `rightalt+capslock = capslock` in
# keyd's [main] layer, which keyd reads as a chord (both keys struck within
# its 50 ms chord_timeout), not as CapsLock pressed while RightAlt is held.
# The shipped file now puts CapsLock in RightAlt's [altgr] layer. This writes
# the new file where /etc/keyd/default.conf is still exactly the one haseen
# wrote before (90a8afd2, its only earlier version) and reloads a running keyd.
# Safe to re-run: any other file, the new one or an administrator's edit
# included, is left alone; without keyd's config there is nothing to do.

# shellcheck source=../lib/common.sh
source "$HASEEN_PATH/lib/common.sh"

KEYD_CONF=/etc/keyd/default.conf
# sha256 of share/haseen/default/keyd/default.conf as 90a8afd2 shipped it.
OLD_SHA=69597b9eed9ea953875a526d6c49157212a88ea7eb2adcd614a2a8e3ce51dd1a

live="$(sysroot_path "$KEYD_CONF")"
[[ -f $live && -r $live ]] || exit 0
[[ "$(sha256sum <"$live")" == "$OLD_SHA  -" ]] || exit 0

info "$KEYD_CONF: RightAlt + CapsLock was a 50 ms chord; CapsLock under a held RightAlt is Caps Lock now"
write_root_file "$KEYD_CONF" 0644 <"$HASEEN_PATH/default/keyd/default.conf"
# keyd reads its config when it starts; a running one is told to read it now.
if ! in_sysroot && systemctl is-active --quiet keyd.service 2>/dev/null; then
    run_root keyd reload
fi
