// Adapted from Omarchy shell/plugins/bar/widgets/Tray.qml (TrayIcon).
// MIT, Copyright (c) David Heinemeier Hansson.
// haseen: own file; no MultiEffect recolouring of symbolic icons, because the
// shell renders with QT_QUICK_BACKEND=software (no shaders, architecture 6).
import QtQuick

// A tray icon, decoded at physical pixels: IconImage uses the logical size,
// which leaves PNG icons upscaled and blurry on HiDPI displays.
Image {
    required property var icon

    fillMode: Image.PreserveAspectFit
    sourceSize.width: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
    sourceSize.height: Math.round(Math.min(width, height) * Screen.devicePixelRatio)
    // Quickshell already resolves the icon into an image:// URL, with a
    // "?path=" fallback for apps that ship icons outside a theme.
    source: String(icon || "")
}
