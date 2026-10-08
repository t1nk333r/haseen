.pragma library

// Read-only evidence is not an executable plan. The CLI owns inventory and
// ownership policy; this model rejects malformed identities and unknown enums.
var pages = ["overview", "tools", "services", "local"];
var families = ["ssh", "postgresql", "apache", "nginx", "beef"];
var localIds = ["listener", "http-server", "enumeration-host", "proxy-ca", "remmina"];
var verbs = ["net-listener", "net-http-server", "net-file-server", "net-proxy-ca", "net-remmina"];
var pending = null;
function text(value) { return String(value === null || value === undefined ? "" : value).replace(/[\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]/g, ""); }
function output(value) { return String(value || "").replace(/[\x00-\x08\x0b-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]/g, ""); }
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
        if (d.anchor !== null && (!d.anchor || !/^[A-F0-9]{64}$/.test(d.anchor.sha256) || typeof d.anchor.unchanged !== "boolean")) return null;
    } else return null;
    return d;
}
function route(page, itemId) {
    if (!member(page, pages) || (itemId !== "" && !identity(itemId))) return false;
    pending = {page: page, itemId: itemId};
    return true;
}
function consume() { var r = pending; pending = null; return r; }
function filterTools(rows, query, group) {
    var q = query.toLowerCase();
    return rows.filter(function(r) { return (!group || r.groups.indexOf(group) >= 0) && (r.id + " " + r.groups.join(" ") + " " + r.packages.map(function(p) { return p.name; }).join(" ")).toLowerCase().indexOf(q) >= 0; }).sort(function(a,b) { return a.id < b.id ? -1 : a.id > b.id ? 1 : 0; });
}
function toolState(t) {
    if (t.state === "missing") return t.resolution && t.resolution.state === "resolved" ? "Resolved, not installed" : "Not installed";
    if (t.state !== "installed") return "Unknown / unavailable";
    if (!t.entrypoints.length) return "No verified executable entrypoint";
    if (t.entrypoints.length > 1) return "Choose entrypoint";
    return "Installed • " + (t.entrypoints[0].usage.state === "ready" ? "Documentation available" : "Documentation unavailable");
}
function entry(t, id) { return t && t.entrypoints.find(function(e) { return e.id === id; }); }
function toolArgv(cli, t, entryId, verb) {
    var e = entry(t, entryId);
    if (!path(cli) || !t || !tool(t) || t.state !== "installed" || !e || e.usage.state !== "ready" || !member(verb, ["tool-help", "tool-run"])) return [];
    return [cli, "vapt", verb, t.id, "--entry", e.id];
}
function serviceArgv(cli, s, verb) {
    if (!path(cli) || !s || !service(s) || !s.installed || s.ownership !== "verified" || !s.unit || !s.fragmentPath || !member(verb, ["service-start", "service-stop", "service-restart"]) || s.state === "transitioning" || (s.state === "unknown" && verb !== "service-stop")) return [];
    return [cli, "vapt", verb, s.id, "--expect-unit", s.unit, "--expect-fragment", s.fragmentPath];
}
function addressError(value) {
    if (!value) return "Choose a local bind address.";
    if (!string(value)) return "Use a local IP address, not a hostname or URL.";
    var parts = value.split("%"), literal = parts[0];
    if (parts.length > 2 || (parts.length === 2 && !/^[A-Za-z0-9_.-]{1,64}$/.test(parts[1]))) return "Use one local interface scope (1–64 letters, digits, _, . or -).";
    if (literal.indexOf(":") < 0) {
        if (parts.length !== 1 || !/^\d{1,3}(\.\d{1,3}){3}$/.test(literal) || !literal.split(".").every(function(v) { return Number(v) <= 255 && (v === "0" || v[0] !== "0"); })) return "Use a local IP address, not a hostname or URL.";
        return "";
    }
    // Validate the literal separately; an embedded IPv4 tail occupies two groups.
    var tail = literal.split(":").pop();
    if (tail.indexOf(".") >= 0) {
        if (addressError(tail)) return "Use a valid numeric IPv6 literal.";
        literal = literal.slice(0, literal.length - tail.length) + "0:0";
    }
    if (!/^[0-9a-fA-F:]+$/.test(literal) || literal.indexOf(":::") >= 0 || literal.split("::").length > 2) return "Use a valid numeric IPv6 literal.";
    var compressed = literal.indexOf("::") >= 0;
    var groups = literal.split(":").filter(function(v) { return v !== ""; });
    if (!groups.every(function(v) { return /^[0-9a-fA-F]{1,4}$/.test(v); }) || (compressed ? groups.length >= 8 : groups.length !== 8 || literal[0] === ":" || literal.slice(-1) === ":")) return "Use a valid numeric IPv6 literal.";
    if (/^fe[89ab][0-9a-f]:/i.test(literal) && parts.length !== 2) return "Choose a local interface scope for this link-local address.";
    return "";
}
function endpointErrors(d, variant) {
    return {
        address: addressError(d.address),
        port: !d.port ? "Enter a port." : !/^\d+$/.test(d.port) || Number(d.port) < 1024 || Number(d.port) > 65535 ? "Use a whole-number port from 1024 to 65535. Local helpers do not elevate." : "",
        path: variant !== "listener" && !path(d.path) ? variant === "http-server" ? "Choose an absolute directory path to serve." : "Choose one absolute installed package-owned file path to serve." : ""
    };
}
function endpointError(d, variant) {
    var errors = endpointErrors(d, variant);
    return errors.address || errors.port || errors.path;
}
function localArgv(cli, c, draft, operation) {
    if (!path(cli) || !c || !capability(c) || !c.installed || member(c.state, ["missing", "unknown", "refused"])) return [];
    var a = [cli, "vapt", c.command];
    if (c.id === "remmina") return c.available ? a : [];
    if (c.id === "proxy-ca") {
        if (operation === "trust" && path(draft.path)) return a.concat(["trust", draft.path]);
        if (operation === "remove" && /^[A-F0-9]{64}$/.test(draft.fingerprint)) return a.concat(["remove", draft.fingerprint]);
        return [];
    }
    if (endpointError(draft, c.id)) return [];
    if (c.id === "listener") return a.concat(["--bind", draft.address, draft.port]);
    if (c.id === "http-server") return a.concat(["--bind", draft.address, draft.path, draft.port]);
    return a.concat(["--file", draft.path, "--bind", draft.address, draft.port]);
}
function dryRun(argv) { return argv.length ? argv.slice(0,3).concat(["--dry-run"], argv.slice(3)) : []; }
function terminal(cli, argv) { return path(cli) && argv.length && argv[0] === cli ? [cli, "config", "terminal", "--"].concat(argv) : []; }
function fingerprint(value) { return (String(value || "").match(/.{1,2}/g) || []).join(":"); }
function groups(tools) {
    var out = [];
    tools.forEach(function(t) { t.groups.forEach(function(g) { if (out.indexOf(g) < 0) out.push(g); }); });
    return ["All groups"].concat(out.sort());
}
function ownedFiles(tools) {
    var out = [];
    tools.forEach(function(t) { t.packages.forEach(function(p) { p.files.forEach(function(f) { if (path(f) && out.indexOf(f) < 0) out.push(f); }); }); });
    return out.sort();
}
function serviceState(s) {
    if (s.state === "transitioning") return s.activeState === "activating" ? "Starting…" : s.activeState === "deactivating" ? "Stopping…" : "Reloading…";
    return {running: "Running", stopped: "Stopped", failed: "Failed", unknown: "State unknown"}[s.state] || "State unknown";
}
