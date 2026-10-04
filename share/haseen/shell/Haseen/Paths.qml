pragma Singleton

import QtQuick
import Quickshell

// Path constants. Mirrors share/haseen/lib/common.sh: HASEEN_USER_CONFIG and
// HASEEN_USER_STATE win over the XDG defaults, so the CLI and the shell always
// look at the same files.
Singleton {
    readonly property string home: Quickshell.env("HOME") || ""
    readonly property string configHome: Quickshell.env("XDG_CONFIG_HOME") || home + "/.config"
    readonly property string stateHome: Quickshell.env("XDG_STATE_HOME") || home + "/.local/state"

    // The running config is $HASEEN_PATH/shell; fall back to its parent when
    // the shell was started by hand without the environment.
    readonly property string shellDir: Quickshell.shellDir
    readonly property string haseenPath: Quickshell.env("HASEEN_PATH") || shellDir.replace(/\/shell\/?$/, "")

    readonly property string userConfig: Quickshell.env("HASEEN_USER_CONFIG") || configHome + "/haseen"
    readonly property string userState: Quickshell.env("HASEEN_USER_STATE") || stateHome + "/haseen"

    readonly property string defaultShellConfig: haseenPath + "/default/shell.json"
    readonly property string userShellConfig: userConfig + "/shell.json"
    readonly property string themeTokens: userState + "/current/theme/shell.json"

    // Search order (architecture 5.2): the user copy wins over the built-in.
    readonly property string userPlugins: userConfig + "/plugins"
    readonly property string builtinPlugins: shellDir + "/plugins"

    function fileUrl(path: string): string {
        return "file://" + path;
    }
}
