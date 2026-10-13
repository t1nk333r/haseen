.pragma library

// The VAPT CLI's JSON contract (plan 088). haseen.menu's Security providers
// and the optional haseen.security panel both validate with it, so neither
// imports the other's files and the menu loads without the panel's directory.
// The CLI owns inventory and ownership policy; this only refuses malformed
// identities and unknown enums. Nothing here executes or persists.
var pages = ["overview", "tools", "services", "local"];
var families = ["ssh", "postgresql", "apache", "nginx", "beef"];
var localIds = ["listener", "http-server", "enumeration-host", "proxy-ca", "remmina"];
var verbs = ["net-listener", "net-http-server", "net-file-server", "net-proxy-ca", "net-remmina"];
function string(value) { return typeof value === "string" && !/[\x00-\x1f\x7f-\x9f]/.test(value); }
function identity(value) { return string(value) && /^[a-z0-9][a-z0-9+_.-]*$/.test(value); }
function path(value) { return string(value) && value[0] === "/"; }
function member(value, allowed) { return allowed.indexOf(value) >= 0; }
function strings(value) { return Array.isArray(value) && value.every(string); }
function unique(rows, check) {
    if (!Array.isArray(rows)) return false;
    var seen = {};
    return rows.every(function(r) {
        if (!r || !identity(r.id) || seen[r.id] || !check(r)) return false;
        seen[r.id] = true;
        return true;
    });
}
function tool(r) {
    if (!member(r.state, ["installed", "missing", "unknown"]) || !string(r.reason) || !strings(r.groups) || typeof r.dataOnly !== "boolean" || !Array.isArray(r.packages) || !Array.isArray(r.entrypoints)) return false;
    if (!r.packages.every(function(p) { return p && identity(p.name) && string(p.version) && strings(p.source) && member(p.provenance, ["verified", "unknown"]) && strings(p.files); })) return false;
    if (!Array.isArray(r.desktopEntries) || !r.desktopEntries.every(function(d) { return d && path(d.path) && string(d.name) && typeof d.terminal === "boolean"; })) return false;
    if (r.native !== null && (!r.native || !member(r.native.state, ["exact", "missing", "unknown", "drifted"]) || !string(r.native.spec) || !strings(r.native.files) || !Array.isArray(r.native.entrypoints))) return false;
    var seen = {};
    return r.entrypoints.every(function(e) {
        if (!e || !path(e.id) || e.id !== e.path || seen[e.id] || !member(e.kind, ["executable", "native"]) || !Array.isArray(e.documentation) || !e.usage) return false;
        seen[e.id] = true;
        return e.documentation.every(function(d) { return d && path(d.path) && member(d.kind, ["man", "document"]); }) && member(e.usage.state, ["ready", "unavailable"]) && member(e.usage.kind, [null, "man", "document", "reviewed-argv"]) && string(e.usage.reason);
    });
}
function service(r) {
    return member(r.id, families) && typeof r.installed === "boolean" && member(r.ownership, ["verified", "missing", "ambiguous", "refused", "unknown"]) && member(r.state, ["running", "stopped", "transitioning", "failed", "unknown"]) && string(r.reason) && (r.package === null || identity(r.package)) && (r.unit === null || string(r.unit)) && (r.fragmentPath === null || path(r.fragmentPath)) && (r.activeState === null || string(r.activeState)) && (r.subState === null || string(r.subState)) && r.exposure === "unknown";
}
function capability(r) {
    var at = localIds.indexOf(r.id);
    return at >= 0 && r.command === verbs[at] && typeof r.installed === "boolean" && typeof r.available === "boolean" && (!r.available || r.installed) && (r.available === (r.state === "available")) && member(r.state, ["available", "missing", "selection-required", "unknown", "refused"]) && strings(r.prerequisitePackages) && string(r.reason);
}
function settings(s) {
    return s && s.schemaVersion === 1 && typeof s.showLocalAddresses === "boolean" && (s.enumerationScript === null || path(s.enumerationScript)) && string(s.bindAddress);
}
// One `--json` answer of `haseen vapt <kind>`, or null when any part of it
// is malformed: a bad row refuses the whole section.
function parse(kind, raw) {
    var d;
    try { d = JSON.parse(raw); } catch (_) { return null; }
    if (!d || d.schemaVersion !== 1) return null;
    if (kind === "tools" || kind === "status" || kind === "doctor") {
        if (!unique(d.tools, tool) || !Array.isArray(d.sources) || !d.sources.every(function(s) { return s && identity(s.name) && member(s.state, ["safe", "unavailable"]) && typeof s.cachedPackages === "number" && s.cachedPackages >= 0; }) || !d.privateSource || !string(d.privateSource.reason) || !member(d.privateSource.state, ["absent", "usable", "unverified", "broken", "unsupported-architecture"])) return null;
        if (kind !== "tools" && (!d.provisioning || !member(d.provisioning.state, ["healthy", "missing", "degraded"]) || !member(d.provisioning.exitCode, [0, 1, 2]) || !strings(d.provisioning.diagnostics) || !d.workflow || !settings(d.workflow.settings) || typeof d.workflow.entrypoints !== "number" || typeof d.workflow.documentationReady !== "number")) return null;
        if (kind === "doctor" && !unique(d.workflow.capabilities, capability)) return null;
    } else if (kind === "services") {
        if (!unique(d.services, service)) return null;
    } else if (kind === "menu") {
        if (d.plugin !== "haseen.security" || typeof d.enabled !== "boolean") return null;
    } else if (kind === "sources") {
        if (!Array.isArray(d.repositories) || !d.repositories.every(function(r) { return r && r.name === "oniomarchy" && string(r.reason) && string(r.state); })) return null;
    } else if (kind === "addresses") {
        if (!Array.isArray(d.addresses) || !d.addresses.every(function(a) { return a && string(a.interface) && string(a.address) && member(a.family, ["ipv4", "ipv6"]) && member(a.scope, ["loopback", "link", "global"]) && typeof a.prefixLength === "number"; })) return null;
    } else if (kind === "certificate") {
        if (!member(d.state, ["valid", "invalid", "refused"]) || !string(d.reason)) return null;
        if (d.certificate !== null && (!d.certificate || !/^[A-F0-9]{64}$/.test(d.certificate.sha256) || !string(d.certificate.subject) || !string(d.certificate.issuer) || !string(d.certificate.notBefore) || !string(d.certificate.notAfter) || typeof d.certificate.isCa !== "boolean" || typeof d.certificate.containsPrivateKey !== "boolean")) return null;
        if (d.state === "valid" && (!d.certificate || !d.certificate.isCa || d.certificate.containsPrivateKey)) return null;
    } else if (kind === "anchor") {
        if (!member(d.state, ["none", "owned", "foreign", "modified", "unknown", "refused"]) || !string(d.reason)) return null;
        if (d.state === "refused" && d.anchor === undefined) d.anchor = null;
        if (d.anchor !== null && (!d.anchor || !/^[A-F0-9]{64}$/.test(d.anchor.sha256) || typeof d.anchor.unchanged !== "boolean" || (d.anchor.transaction !== undefined && !member(d.anchor.transaction, ["pending", "removing", "created"])))) return null;
    } else return null;
    return d;
}
