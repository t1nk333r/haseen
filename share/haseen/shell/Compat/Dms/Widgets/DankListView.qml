import QtQuick

// qs.Widgets.DankListView for DankMaterialShell plugins (architecture 5.4):
// a vertical ListView that stops at its bounds. The property names and the
// flick constants follow dank-qml-common DCommon/Widgets/DListView.qml and
// ScrollConstants.js, which DMS's DankListView wraps (MIT, Copyright (c)
// 2025-2026 Avenge Media LLC). DMS's own wheel momentum, row transitions and
// selection highlight are not provided: the wheel scrolls as Qt's ListView
// does, and the properties that steer them are accepted and ignored.
ListView {
    property real scrollBarTopMargin: 0
    property bool showScrollBar: true
    property real mouseWheelSpeed: 60
    property real savedY: 0
    property bool justChanged: false
    property bool isUserScrolling: false
    property real momentumVelocity: 0
    property bool isMomentumActive: false
    property real friction: 0.96
    property bool highlightSelection: false
    property bool animateSelection: true

    function stopMomentum() {
        cancelFlick();
    }

    flickDeceleration: 1500
    maximumFlickVelocity: 2000
    boundsBehavior: Flickable.StopAtBounds
    boundsMovement: Flickable.FollowBoundsBehavior
    pressDelay: 0
    flickableDirection: Flickable.VerticalFlick
}
