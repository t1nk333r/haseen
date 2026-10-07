// Web search model for haseen.websearch (plan 081): the URL a query opens
// and the argv that opens it. The shell itself makes no request: xdg-open
// hands the URL to the default browser.
.pragma library

var DEFAULT_TEMPLATE = "https://duckduckgo.com/?q=%s";

// Only http(s) URLs with a fixed host and a %s slot after it. A file:,
// javascript: or custom-scheme template would let a setting open anything
// through xdg-open, so it is refused rather than repaired. The authority
// (everything up to the first / ? #) must be a plain host name, IPv4 or
// bracketed IPv6 address with an optional port: no %s (the query would pick
// the destination: "https://search.%s/"), no userinfo, no percent escapes,
// no backslash (browsers read "\" as "/", which moves the authority).
function validTemplate(template) {
    const t = String(template || "").trim();
    if (/[\s\\]/.test(t))
        return false;
    const m = /^https?:\/\/([^\/?#]*)([\/?#].*)$/i.exec(t);
    if (!m)
        return false;
    const authority = /^(?:[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.)*[a-z0-9](?:[a-z0-9-]*[a-z0-9])?\.?(?::[0-9]{1,5})?$|^\[[0-9a-f:.]+\](?::[0-9]{1,5})?$/i;
    return authority.test(m[1]) && m[2].indexOf("%s") >= 0;
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
