# shellcheck shell=bash
# fontconfig. Sourced by bin/haseen-seed-user.
#
# haseen:seed $CONFIG/fontconfig/fonts.conf|theme fonts + Arabic script fallback
#
# Generated, not copied, for the same reason as XCompose: it carries absolute
# paths. Two includes, in this order:
#   1. the theme render, which assigns the generic families (assign replaces
#      the whole list, so it must run first);
#   2. haseen's static Arabic script rules, which test lang and still fire
#      afterwards.
# Both are ignore_missing: a home with no theme applied yet still gets valid
# fontconfig, and `fc-match` keeps working.
seed_main() {
    local f="$CONFIG/fontconfig/fonts.conf"
    # -L too: a dangling link is the user's, never written through.
    [[ -e $f || -L $f ]] && return 0
    write_user_file "$f" <<EOF
<?xml version="1.0"?>
<!DOCTYPE fontconfig SYSTEM "urn:fontconfig:fonts.dtd">
<!-- Your fontconfig. haseen writes this file once and never again; add your
     own rules below the includes, which override what they set. -->
<fontconfig>
  <include ignore_missing="yes">$HASEEN_USER_STATE/current/theme/fonts.conf</include>
  <include ignore_missing="yes">$DEFAULTS/fontconfig/arabic.conf</include>
</fontconfig>
EOF
}
