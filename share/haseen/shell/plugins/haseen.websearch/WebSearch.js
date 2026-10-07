// Web search model for haseen.websearch (plan 081): the URL a query opens
// and the argv that opens it. The shell itself makes no request: xdg-open
// hands the URL to the default browser.
.pragma library

var DEFAULT_TEMPLATE = "https://duckduckgo.com/?q=%s";

// Only http(s) URLs with a host and a %s slot. A file:, javascript: or
// custom-scheme template would let a setting open anything through
// xdg-open, so it is refused rather than repaired.
function validTemplate(template) {
    const t = String(template || "").trim();
    return /^https?:\/\/[^\s\/?#%]+/i.test(t) && !/\s/.test(t) && t.indexOf("%s") >= 0;
}

// The template's host, shown under the query ("duckduckgo.com").
function host(template) {
    const m = /^https?:\/\/(?:[^@\/?#]*@)?([^\/?#:]+)/i.exec(String(template || "").trim());
    return m ? m[1].toLowerCase() : "";
}

// Every %s becomes the percent-encoded query; "" for an empty query or a
// refused template.
function url(template, query) {
    const q = String(query || "").trim();
    if (q === "" || !validTemplate(template))
        return "";
    return String(template).trim().split("%s").join(encodeURIComponent(q));
}

function openArgv(target) {
    return target ? ["xdg-open", String(target)] : [];
}
