import QtQuick
import Quickshell.Io
import "Model.js" as Model

// One finite read per open/explicit refresh. No sampling, retry or launch.
Process {
    id: root
    property string cli: ""
    property string kind: ""
    property var operands: []
    property int generation: 0
    signal received(string kind, int generation, var data, string error)
    command: [cli, "vapt", {menu: "menu", status: "status", sources: "repo-status", tools: "tool-list", services: "service-list", doctor: "doctor", addresses: "net-addresses", certificate: "net-proxy-ca", anchor: "net-proxy-ca"}[kind]].concat(operands).concat(["--json"])
    stdout: StdioCollector { id: out }
    stderr: StdioCollector { id: err }
    onExited: code => {
        const data = Model.parse(kind, out.text);
        // Valid semantic degraded/refused objects remain diagnostics, not success.
        const semantic = ["status", "doctor", "certificate", "anchor"].indexOf(kind) >= 0;
        root.received(kind, generation, data && (code === 0 || semantic) ? data : null,
            data && (code === 0 || semantic) ? "" : "Unsupported or unreadable local status data. " + Model.text(err.text));
    }
}
