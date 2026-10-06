// Adapted from Omarchy shell/Ui/KeyboardPanel.qml.
// MIT, Copyright (c) David Heinemeier Hansson.
// haseen compatibility: palette and geometry follow qs.Haseen theme tokens.
import QtQuick
import Quickshell
import Quickshell.Wayland
import qs.Commons
import "PanelInput.js" as PanelInput

// Layer-shell popup attached to a bar widget icon, designed for
// click-driven AND keyboard-driven panels (e.g. SUPER+CTRL+W summon).
//
// Built on PanelWindow with a brief WlrKeyboardFocus.Exclusive prime followed
// by OnDemand rather than PopupWindow (xdg-popup). The prime acquires focus
// both when the surface maps and when it reopens while still mapped for its
// fade-out. xdg-popups don't get that — they only receive keys after a
// click/hover routes focus through their parent surface — so keyboard-summoned
// popups fell flat without it.
//
// Exclusive would also grant map-time focus, but it makes Hyprland route
// *every* pointer event to the exclusive surface no matter which output
// the cursor is over, which leaves clicks on any other monitor unable to
// reach the dismissal surfaces below.
//
// API is a subset of Common.PopupCard: anchorItem, owner, bar, open,
// padding, margin, contentWidth/Height, centerOnBar, default contentItem.
// Missing on purpose (for now): triggerMode ("hover"), containsMouse.
//
// Positioning: full-screen layer-shell with the card placed inside at
// `cardOrigin`. We use the bar window's height/width for the perpendicular
// axis (away-from-bar) because mapToItem on the anchor returns
// bar-content-relative coords with internal layout offsets baked in
// (e.g. ~13px from the bar's vertical centering of its widget row). The
// parallel axis (along-the-bar) uses the anchor's content x/y since the
// bar spans full screen on that axis.
//
// Outside-click dismissal: an overlay MouseArea catches clicks, with the
// QsWindow.mask subtracting the bar strip so clicks on the bar still
// reach the bar widgets (activePopout coordinator hands off to another
// popup if the user clicks a different bar icon).
PanelWindow {
  id: root

  required property Item anchorItem
  required property QtObject bar
  property var owner: null
  property int margin: Style.gapsOut
  property int padding: Style.spacing.popupPadding
  property int contentWidth: Style.space(280)
  property int contentHeight: Style.space(200)
  property var borderSpec: Border.surfaceSpec("popups", "border", Color.popups.border, Math.max(1, Style.space(2)))
  property bool centerOnBar: false
  property bool open: false
  property int gap: Style.gapsOut  // distance between bar edge and panel
  property bool popoutSwitching: false
  property bool popoutSwitchClosing: false
  property bool focusPrimed: false

  // Item that should take keyboard focus once the panel maps. Typically a
  // PanelKeyCatcher inside the panel content. Layer-shell grants focus to the
  // surface during the Exclusive prime, but Qt still needs an active-focus
  // target inside the surface for Keys.onPressed handlers to fire. Schedule
  // the focus through Qt.callLater so it runs after the surface is fully
  // mapped and child items have completed layout.
  property Item focusTarget: null

  default property alias contentItem: contentHolder.children

  // Inline children retain their original ID scope. New callers can supply a
  // Component instead: it is created only on open and released after fade-out.
  property Component contentComponent: null
  readonly property alias loadedContent: lazyContent.item

  function focusContent() {
    Qt.callLater(function() {
      if (!root.open) return
      var target = root.focusTarget || lazyContent.item || contentHolder
      target.forceActiveFocus()
    })
  }

  readonly property var coordinatorKey: owner || root
  readonly property var anchorWindow: anchorItem ? anchorItem.QsWindow.window : null
  readonly property string barPos: bar ? bar.position : "top"

  function close() {
    if (owner && "close" in owner) owner.close()
    else root.open = false
  }

  function beginFocusPrime() {
    if (open && backingWindowVisible) focusPrimeTimer.restart()
  }

  // --- screen + lifetime ---------------------------------------------------

  screen: anchorWindow ? anchorWindow.screen : null
  visible: open || card.opacity > 0 || popoutSwitching
  color: "transparent"
  exclusionMode: ExclusionMode.Ignore

  WlrLayershell.namespace: "omarchy-keyboard-panel"
  WlrLayershell.layer: WlrLayer.Overlay
  // Keyboard focus follows `open` (NOT `visible`). The window remains
  // mapped during the fade-out so the opacity animation has something to
  // animate, but keyboard/click ownership must release the moment the
  // logical close fires — otherwise the user is locked out for 140ms.
  //
  // Prime with Exclusive on every open, then settle on OnDemand. Hyprland
  // focuses OnDemand when a surface first maps, but not when an already-mapped
  // fade-out surface changes from None back to OnDemand. Exclusive also takes
  // focus when the previously focused application has constrained the pointer.
  // The brief prime covers both cases; OnDemand then releases compositor-wide
  // pointer hit-testing so clicks can reach the dismissal windows below.
  WlrLayershell.keyboardFocus: open
    ? (focusPrimed ? WlrKeyboardFocus.OnDemand : WlrKeyboardFocus.Exclusive)
    : WlrKeyboardFocus.None

  onBackingWindowVisibleChanged: {
    beginFocusPrime()
    if (backingWindowVisible) focusContent()
  }

  // Full-screen layer-shell. The visible card is positioned inside via
  // `cardOrigin`; the overlay below the card catches a click anywhere else
  // and dismisses, except in the bar strip, where the click is forwarded to
  // the bar button under it (so the user can swap to another bar icon's
  // popup in one click and the activePopout coordinator hands over).
  anchors {
    top: true
    bottom: true
    left: true
    right: true
  }

  // Size of the bar strip, where clicks are forwarded to registered bar
  // buttons instead of dismissing, even though the overlay surface sits
  // above the bar.
  readonly property real _barStripSize: {
    if (!bar) return 0
    var actual = (root.barPos === "top" || root.barPos === "bottom") ? root.barH : root.barW
    return Math.max(bar.barSize, actual) + root.gap
  }
  // Clickable region while the panel is open. A panel may replace `mask`
  // with one of its own (the flea-shelf drag empties its mask so a carried
  // item can be dropped into the application underneath), so the
  // closed-state restriction below is applied to whichever mask is in
  // force, not to this one.
  property Region openMask: Region {
    width: root.screenW
    height: root.screenH
  }

  // No pointer input at all. The surface stays mapped for the ~140 ms
  // fade-out after the logical close, and a mapped full-screen surface
  // swallows every click meant for the application or the bar below it.
  property Region closedMask: Region {}

  mask: openMask

  // The mask the panel asked for — ours by default, the plugin's when it
  // supplied one. Remembered rather than overwritten, so reopening hands
  // the plugin's own Region (with its bindings intact) back to the surface.
  property Region suppliedMask: null
  property bool applyingMask: false

  // Applies the closed-state restriction to whichever mask is in force and
  // hands the panel's own mask back, bindings intact, when it reopens.
  function applyMask() {
    var wanted = PanelInput.effectiveMask(root.open, root.suppliedMask, root.closedMask)
    if (root.mask === wanted) return
    root.applyingMask = true
    root.mask = wanted
    root.applyingMask = false
  }

  // Records what the panel asked for, then applies the closed-state rule.
  // On creation the `mask` binding notifies first and applyMask() swaps in
  // `closedMask` before Component.onCompleted runs, so `mask` there is our
  // own empty region: adopting it as the panel's request would leave every
  // open panel without pointer input (no hover, clicks, outside dismissal).
  function adoptMask() {
    if (applyingMask) return
    suppliedMask = PanelInput.suppliedMask(root.mask, root.suppliedMask, root.closedMask)
    applyMask()
  }

  onMaskChanged: adoptMask()

  Component.onCompleted: adoptMask()

  // True while the surface must take no pointer input: the panel is
  // logically closed (the surface outlives it for the fade), or the mask in
  // force is empty because the panel asked for it. The dismissal twins on
  // the other outputs follow this, not `open` alone.
  readonly property bool pointerInputSuspended: PanelInput.pointerInputSuspended(root.open, root.mask)

  // Track every layout change between the bar's contentItem and the
  // anchor item. `transform` updates whenever any item in that chain
  // moves/resizes, which is what makes the position binding below
  // actually reactive — mapToItem on its own is a one-shot.
  TransformWatcher {
    id: anchorWatcher
    a: anchorWindow ? anchorWindow.contentItem : null
    b: anchorItem
  }

  // Anchor item's position within the bar's content surface. For a
  // full-width top bar, the content x maps directly to screen x; the y
  // returned here has the bar's internal padding baked in (e.g. ~13px
  // from vertical centering of the widget row), which is why `cardOrigin`
  // below uses `barH` for the perpendicular axis instead of this y.
  readonly property point anchorScreenPos: {
    anchorWatcher.transform  // reactive dependency
    if (!anchorItem || !anchorWindow) return Qt.point(0, 0)
    return anchorItem.mapToItem(anchorWindow.contentItem, 0, 0)
  }
  readonly property real anchorW: anchorItem ? anchorItem.width : 0
  readonly property real anchorH: anchorItem ? anchorItem.height : 0
  readonly property real screenW: screen ? screen.width : 0
  readonly property real screenH: screen ? screen.height : 0
  readonly property real availableCardWidth: screenW > 0
    ? Math.max(120, screenW - ((barPos === "left" || barPos === "right") ? barW + gap + margin : margin * 2))
    : 0
  readonly property real availableCardHeight: screenH > 0
    ? Math.max(120, screenH - ((barPos === "top" || barPos === "bottom") ? barH + gap + margin : margin * 2))
    : 0
  readonly property real verticalContentInset: padding * 2 + Border.top(borderSpec) + Border.bottom(borderSpec)

  function fittedContentWidth(width, cap) {
    var desired = Math.max(1, Number(width) || 1)
    var maxWidth = root.availableCardWidth > 0 ? root.availableCardWidth : desired
    if (cap !== undefined && Number(cap) > 0) maxWidth = Math.min(maxWidth, Number(cap))
    return Math.round(Math.min(desired, maxWidth))
  }

  function fittedContentHeight(implicitHeight, cap) {
    var desired = Math.max(root.verticalContentInset, (Number(implicitHeight) || 0) + root.verticalContentInset)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    if (cap !== undefined && Number(cap) > 0) maxHeight = Math.min(maxHeight, Number(cap))
    return Math.round(Math.min(desired, maxHeight))
  }

  function cappedContentHeight(height) {
    var desired = Math.max(root.padding * 2, Number(height) || root.padding * 2)
    var maxHeight = root.availableCardHeight > 0 ? root.availableCardHeight : desired
    return Math.round(Math.min(desired, maxHeight))
  }

  // Desired top-left of the card in screen coordinates. For the
  // perpendicular axis (away-from-bar) we anchor to the bar window's edge
  // directly — not the anchor item's y/x — because mapToItem(barContent)
  // returns coordinates in the bar's content space, which can be offset
  // from the bar surface's screen-anchored corner by internal layout
  // (centering wrappers, padding). The bar's surface IS aligned to its
  // anchored screen edge, so using `barW`/`barH` gives the right edge
  // regardless of how the bar's internal widgets are positioned. For the
  // parallel axis (along the bar) the anchor item's reported position is
  // still consistent with the bar content origin, so it's accurate for
  // centering the card under the icon.
  readonly property real barW: anchorWindow ? anchorWindow.width : screenW
  readonly property real barH: anchorWindow ? anchorWindow.height : 0
  readonly property point cardOrigin: {
    if (!anchorItem || !bar) return Qt.point(margin, margin)
    var x = 0, y = 0
    if (centerOnBar && (barPos === "top" || barPos === "bottom")) {
      x = screenW / 2 - contentWidth / 2
      y = barPos === "bottom" ? screenH - barH - contentHeight - gap : barH + gap
    } else if (centerOnBar) {
      x = barPos === "left" ? barW + gap : screenW - barW - contentWidth - gap
      y = screenH / 2 - contentHeight / 2
    } else if (barPos === "bottom") {
      x = anchorScreenPos.x + anchorW / 2 - contentWidth / 2
      y = screenH - barH - contentHeight - gap
    } else if (barPos === "left") {
      x = barW + gap
      y = anchorScreenPos.y + anchorH / 2 - contentHeight / 2
    } else if (barPos === "right") {
      x = screenW - barW - contentWidth - gap
      y = anchorScreenPos.y + anchorH / 2 - contentHeight / 2
    } else { // "top" (default)
      x = anchorScreenPos.x + anchorW / 2 - contentWidth / 2
      y = barH + gap
    }
    x = Math.max(margin, Math.min(x, screenW - contentWidth - margin))
    y = Math.max(margin, Math.min(y, screenH - contentHeight - margin))
    return Qt.point(Math.round(x), Math.round(y))
  }


  // --- popout coordination (same-bar single-popout model) -----------------

  // Coordinate on `open`, not `visible`. `visible` lags into the fade-out
  // animation, which made ownership transfer to a sibling popup race.
  onOpenChanged: {
    // Hand the panel's own mask back when it reopens; take every pointer
    // event away from the surface the moment it closes.
    applyMask()
    if (open) {
      focusPrimed = false
      beginFocusPrime()
      focusContent()
    } else {
      focusPrimeTimer.stop()
      focusPrimed = false
    }
    if (!bar) return
    if (open) {
      popoutSwitchClosing = false
      popoutSwitching = bar.activePopout && bar.activePopout !== coordinatorKey
      bar.requestPopout(coordinatorKey)
      if (popoutSwitching) popoutSwitchTimer.restart()
    } else {
      popoutSwitchClosing = !!(owner && owner.popoutSwitchClosing)
      popoutSwitching = false
      if (bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
      if (popoutSwitchClosing) closeSwitchTimer.restart()
    }
  }

  Component.onDestruction: {
    if (bar && bar.activePopout === coordinatorKey) bar.releasePopout(coordinatorKey)
  }

  // haseen:ui-timeout
  Timer {
    id: focusPrimeTimer
    // Leave enough time for multiple Qt/Wayland commit cycles after the
    // backing window becomes visible while keeping the compositor-wide
    // Exclusive phase imperceptibly short. This interval is covered by the
    // immediate hide/re-summon acceptance case.
    interval: 75
    repeat: false
    onTriggered: if (root.open) root.focusPrimed = true
  }

  // haseen:ui-timeout
  Timer {
    id: popoutSwitchTimer
    interval: 150
    repeat: false
    onTriggered: root.popoutSwitching = false
  }

  // haseen:ui-timeout
  Timer {
    id: closeSwitchTimer
    interval: 1
    repeat: false
    onTriggered: root.popoutSwitchClosing = false
  }

  // --- outside-click dismissal --------------------------------------------

  // Catches clicks anywhere in the clickable region (i.e. everywhere on
  // screen except the bar strip, which is masked out). The card has its
  // own MouseArea below so clicks on it don't bubble up here. Disabled
  // during the fade-out so the dying overlay doesn't swallow clicks that
  // were meant for the apps behind it.
  MouseArea {
    id: dismissArea
    anchors.fill: parent
    enabled: root.open
    acceptedButtons: Qt.AllButtons
    hoverEnabled: true
    property bool hoveringBar: false
    cursorShape: hoveringBar ? Qt.PointingHandCursor : Qt.ArrowCursor

    function inBarRegion(px, py) {
      if (root.barPos === "bottom") return py >= root.screenH - root._barStripSize
      if (root.barPos === "left") return px <= root._barStripSize
      if (root.barPos === "right") return px >= root.screenW - root._barStripSize
      return py <= root._barStripSize
    }

    function barPoint(px, py) {
      if (root.barPos === "bottom") return Qt.point(px, py - (root.screenH - root.barH))
      if (root.barPos === "right") return Qt.point(px - (root.screenW - root.barW), py)
      return Qt.point(px, py)
    }

    function pressTargetAt(px, py) {
      if (!root.anchorWindow || !root.anchorWindow.contentItem || !root.bar || !root.bar.clickTargets) return null
      var p = barPoint(px, py)
      var targets = root.bar.clickTargets
      for (var i = targets.length - 1; i >= 0; i--) {
        var target = targets[i]
        if (!target || !target.triggerPress || target.visible === false || target.opacity === 0 || !target.mapToItem) continue
        if (root.bar.targetBelongsToWindow && !root.bar.targetBelongsToWindow(target, root.anchorWindow)) continue
        var pos = root.anchorWindow.itemPosition(target)
        if (p.x >= pos.x && p.x <= pos.x + target.width && p.y >= pos.y && p.y <= pos.y + target.height) return target
      }
      return null
    }

    function forwardBarClick(px, py, button) {
      if (button !== Qt.LeftButton && button !== Qt.RightButton && button !== Qt.MiddleButton) return false
      var target = pressTargetAt(px, py)
      if (!target) return false
      target.triggerPress(button)
      return true
    }

    onPositionChanged: function(mouse) { hoveringBar = inBarRegion(mouse.x, mouse.y) }
    onExited: hoveringBar = false
    onClicked: function(mouse) {
      // While Exclusive is priming, Hyprland may route a click from another
      // output here with translated coordinates. Never interpret that as a
      // click on this output's bar.
      if (root.focusPrimed && inBarRegion(mouse.x, mouse.y) && forwardBarClick(mouse.x, mouse.y, mouse.button)) return
      root.close()
    }
  }

  // The panel surface only spans the anchor's screen, and the compositor
  // hit-tests pointer input per output, so `dismissArea` above can never see
  // a click on another monitor. Give every other output a transparent twin
  // whose only job is to catch that click. A twin takes pointer input only
  // while the panel itself does: never during the fade-out, and never while
  // the panel has emptied its mask (a drag that must be droppable into the
  // application underneath has to be droppable on every output, not only on
  // the panel's own).
  //
  // Keyboard focus is None: these must catch the pointer without taking focus
  // from the panel when the cursor merely crosses onto their output.
  Variants {
    model: root.open ? Quickshell.screens : []

    delegate: Component {
      PanelWindow {
        required property var modelData

        screen: modelData
        // Compare by output name: the anchor screen must be known before any
        // twin maps, or a twin would cover the panel's own output.
        visible: root.open && !!root.screen && modelData.name !== root.screen.name
        color: "transparent"
        exclusionMode: ExclusionMode.Ignore

        WlrLayershell.namespace: "omarchy-keyboard-panel-dismiss"
        WlrLayershell.layer: WlrLayer.Overlay
        WlrLayershell.keyboardFocus: WlrKeyboardFocus.None

        anchors {
          top: true
          bottom: true
          left: true
          right: true
        }

        // Follows the panel's own input region, so the twins cannot swallow
        // what the panel deliberately lets through.
        mask: Region {
          width: PanelInput.twinSpan(root.pointerInputSuspended, modelData ? modelData.width : 0)
          height: PanelInput.twinSpan(root.pointerInputSuspended, modelData ? modelData.height : 0)
        }

        MouseArea {
          anchors.fill: parent
          enabled: !root.pointerInputSuspended
          acceptedButtons: Qt.AllButtons
          onPressed: root.close()
        }
      }
    }
  }

  // --- card ----------------------------------------------------------------

  BorderSurface {
    id: card
    x: root.cardOrigin.x
    y: root.cardOrigin.y
    width: root.contentWidth
    height: root.contentHeight
    color: Color.popups.background
    borderSpec: root.borderSpec
    padding: root.padding
    radius: Style.cornerRadius
    opacity: root.open || root.popoutSwitching ? 1.0 : 0

    Behavior on opacity {
      enabled: !root.popoutSwitching && !root.popoutSwitchClosing
      NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic }
    }

    // Swallow clicks on the card so they don't bubble to the dismissal
    // MouseArea behind us.
    MouseArea {
      anchors.fill: parent
      acceptedButtons: Qt.AllButtons
    }

    FocusScope {
      id: contentHolder
      enabled: root.open
      visible: root.open || card.opacity > 0
      focus: true
      Keys.onEscapePressed: function(event) {
        root.close()
        event.accepted = true
      }
      anchors.fill: parent
      anchors.topMargin: card.contentTopInset
      anchors.rightMargin: card.contentRightInset
      anchors.bottomMargin: card.contentBottomInset
      anchors.leftMargin: card.contentLeftInset
      opacity: root.popoutSwitching ? (root.open ? 1.0 : 0) : 1.0

      Behavior on opacity {
        enabled: root.popoutSwitching
        NumberAnimation { duration: Style.duration(140); easing.type: Easing.OutCubic }
      }

      Loader {
        id: lazyContent
        anchors.fill: parent
        active: root.open || card.opacity > 0
        sourceComponent: root.contentComponent
        onLoaded: root.focusContent()
      }
    }
  }
}

