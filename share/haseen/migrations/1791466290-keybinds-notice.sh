# shellcheck shell=bash
# The default key layout changed (binds.lua, the owner's layout). binds.lua is
# loaded from the installed tree, so nothing in the user's files needs to
# move; this only says what changed, once, in the output of `haseen migrate`
# (the login notice runs it in a terminal that stays open).
# Safe to re-run: it writes nothing.

# shellcheck source=../lib/common.sh
source "$HASEEN_PATH/lib/common.sh"

info "the default keybindings changed:"
info "  SUPER + F1 opens the keybindings sheet (was SUPER + /)"
info "  ALT + V opens clipboard history (was SUPER + CTRL + V)"
info "  SUPER + Q closes a window too; SUPER + H/J/K/L move focus; SUPER + SHIFT + H/J/K/L move the window"
info "  ALT + J toggles the split (was SUPER + J); ALT + L toggles the workspace layout"
info "  SUPER + SHIFT + <n> moves a window without following it; add ALT to follow"
info "  HYPER (SUPER + SHIFT + ALT + CTRL) + H/J/K/L, [ ] ' \\, G, F or M snap the window"
info "a key your ~/.config/hypr/bindings.lua also binds now fires both actions: hl.unbind() it there first, or move yours"
info "the full list: SUPER + F1, or: haseen keybinds"
