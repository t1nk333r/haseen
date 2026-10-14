.pragma library
.import "../../Haseen/SecurityEvidence.js" as Evidence

// Panel-side filtering, copy and argv over evidence that SecurityEvidence.js
// validated. Argv is built here and run by Apps.launch or the preview
// Process; nothing here executes or persists.
var pages = Evidence.pages;
var families = Evidence.families;
var localIds = Evidence.localIds;
var path = Evidence.path;
var member = Evidence.member;
var parse = Evidence.parse;
function text(value) { return String(value === null || value === undefined ? "" : value).replace(/[\x00-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]/g, ""); }
function output(value) { return String(value || "").replace(/[\x00-\x08\x0b-\x1f\x7f-\x9f\u202a-\u202e\u2066-\u2069]/g, ""); }
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
    if (!path(cli) || !t || !Evidence.tool(t) || t.state !== "installed" || !e || e.usage.state !== "ready" || !member(verb, ["tool-help", "tool-run"])) return [];
    return [cli, "vapt", verb, t.id, "--entry", e.id];
}
function serviceArgv(cli, s, verb) {
    if (!path(cli) || !s || !Evidence.service(s) || !s.installed || s.ownership !== "verified" || !s.unit || !s.fragmentPath || !member(verb, ["service-start", "service-stop", "service-restart"]) || s.state === "transitioning" || (s.state === "unknown" && verb !== "service-stop")) return [];
    return [cli, "vapt", verb, s.id, "--expect-unit", s.unit, "--expect-fragment", s.fragmentPath];
}
function addressError(value) {
    if (!value) return "Choose a local bind address.";
    if (!Evidence.string(value)) return "Use a local IP address, not a hostname or URL.";
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
    if (!path(cli) || !c || !Evidence.capability(c) || !c.installed || member(c.state, ["missing", "unknown", "refused"])) return [];
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
// anchorRemoval and anchorTrust mirror workflow_ca.py remove_allowed and
// trust_allowed: an interrupted transaction (state unknown) is offered even
// when its anchor is missing or partial, because the CLI can finish it.
function anchorRemoval(a) {
    return !!(a && a.anchor && ((a.state === "owned" && a.anchor.unchanged) ||
        (a.state === "unknown" && (a.anchor.transaction === "removing" || a.anchor.transaction === "pending"))));
}
function anchorTrust(a, inspection) {
    if (!a || !inspection || inspection.state !== "valid" || !inspection.certificate) return false;
    return a.state === "none" || !!(a.anchor && a.anchor.sha256 === inspection.certificate.sha256 &&
        ((a.state === "owned" && a.anchor.unchanged) || (a.state === "unknown" && a.anchor.transaction === "pending")));
}
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
