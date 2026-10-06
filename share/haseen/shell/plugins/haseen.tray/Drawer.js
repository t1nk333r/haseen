.pragma library

// When the tray drawer shows its icons. Pinned (the chevron click) keeps it
// open; otherwise hovering the chevron or the icons reveals it, an open item
// menu holds it while the pointer is in the menu, and a short grace after
// the pointer leaves (or the menu closes) keeps it from snapping shut while
// the pointer crosses a gap.
function isOpen(state) {
    return state.pinned === true || state.hovered === true || state.menuOpen === true || state.lingering === true;
}

// Whether losing the hover (or closing the menu) starts the grace: only when
// nothing else still holds the drawer open.
function startsGrace(state) {
    return state.pinned !== true && state.hovered !== true && state.menuOpen !== true;
}
