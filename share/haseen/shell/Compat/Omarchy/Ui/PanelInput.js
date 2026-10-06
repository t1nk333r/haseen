// Pointer-input policy for KeyboardPanel and its cross-monitor dismissal
// twins. It lives beside the component rather than inside it because a
// layer-shell surface cannot be constructed without a compositor, and these
// are the decisions worth testing headlessly.
.pragma library

// Whether a mask lets no pointer event through at all.
//
// `region` is a Quickshell Region (or anything with the same shape). A null
// mask is not empty: a surface without a mask takes input everywhere. A
// composed region (one with sub-regions) is treated as taking input, because
// what its parts add up to depends on their intersection modes; the surface
// then behaves exactly as it did before, which is the safe direction to err.
function regionIsEmpty(region) {
    if (!region) return false
    if (region.regions && region.regions.length > 0) return false
    var item = region.item
    var width = item ? item.width : region.width
    var height = item ? item.height : region.height
    return !(width > 0 && height > 0)
}

// The mask a panel surface must present. `supplied` is the mask the panel
// asked for — the component's own, or the one a plugin put in its place —
// and `closed` is an empty region. While the panel is logically closed the
// surface outlives it for the fade-out, and a full-screen surface would
// swallow every click meant for whatever is behind it; `supplied` is handed
// back untouched on reopen, so the plugin's own bindings keep driving it.
function effectiveMask(open, supplied, closed) {
    return open ? supplied : closed
}

// The mask a panel asked for, after its surface's `mask` became `current`.
// The host's own empty `closed` region is what the host put there, never
// what the panel asked for: adopting it would leave an open panel without
// any pointer input. That happens on creation, where the `mask` binding
// notifies (and the host swaps in `closed`) before Component.onCompleted
// reads `mask` again.
function suppliedMask(current, supplied, closed) {
    return current === closed ? supplied : current
}

// Whether the surface takes no pointer input, either because the panel is
// closed or because the mask in force is empty (a panel empties its mask
// while a drag must be droppable into the application underneath).
function pointerInputSuspended(open, mask) {
    return !open || regionIsEmpty(mask)
}

// One side of a dismissal twin's input region. The twins mirror the panel:
// whenever the panel takes no pointer input, neither may they, or a drag the
// panel deliberately lets through is still blocked on every other output.
function twinSpan(suspended, size) {
    return suspended ? 0 : (Number(size) || 0)
}
