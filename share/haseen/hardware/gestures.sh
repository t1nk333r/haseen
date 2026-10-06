# shellcheck shell=bash
# gestures — a machine with a touchpad gets haseen.gestures, the port of the
# omagesture Omarchy plugin (github.com/heroesofcode/omagesture, MIT, Copyright
# (c) 2026 Pedro Henrique): three fingers slide between workspaces, four resize
# the focused window, natural scrolling, two-finger right click, and a
# three-finger click-drag that moves windows.
#
# Two steps, both outside the user's own files:
#   - the mapping (the plugin's defaults merged with any shell.json settings)
#     is rendered into toggles/hypr/gestures.lua, which init.lua loads;
#   - the `gestures` flag is set. default/shell.json already lists the widget
#     in bar.right, and it takes no room until this flag exists, so a desktop
#     without a touchpad never shows it and ~/.config/haseen/shell.json is
#     never rewritten to switch it on.
# Delete the flag to hide the widget; `haseen plugin disable haseen.gestures`
# does the same through shell.json.

# shellcheck source=../lib/gestures.sh
source "$HASEEN_PATH/lib/gestures.sh"

gestures_apply true
if [[ -e $GESTURES_FLAG ]]; then
    info "hw gestures: the bar widget is already on"
else
    : | write_user_file "$GESTURES_FLAG"
    $DRY_RUN || info "hw gestures: bar widget on (${GESTURES_FLAG/#$HOME/\~})"
fi
