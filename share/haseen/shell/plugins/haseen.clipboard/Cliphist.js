.pragma library

// `cliphist list` output -> rows for the clipboard panel and launcher
// provider. Pure functions (tests/test-widgets-b.sh runs them).
//
// cliphist prints one `<id>\t<preview>` line per entry, newest first. An image
// entry previews as `[[ binary data 2 KiB png 640x480 ]]`: size, format and
// pixel size (cliphist 0.7.0 `preview()`/`sizeStr()`, units B/KiB/MiB).
// Releases before 0.7 printed a MIME type and no pixel size, so both shapes
// are read. Text previews are whitespace-collapsed and truncated to
// `-preview-width` runes (100 by default), which is why the preview pane has
// to decode an entry to show it in full.

const IMAGE = /^\[\[ binary data .*?\b(png|jpe?g|gif|bmp|webp)\b.*\]\]$/i;
const BINARY = /^\[\[ binary data .*\]\]$/;
const META = /^\[\[ binary data ([0-9.]+) ([KMG]?i?B) (\S+)(?: ([0-9]+)x([0-9]+))? \]\]$/;
const UNITS = {
    B: 1,
    KiB: 1024,
    MiB: 1048576,
    GiB: 1073741824
};

function parse(text) {
    const out = [];
    for (const line of String(text || "").split("\n")) {
        const tab = line.indexOf("\t");
        if (tab <= 0)
            continue;
        const id = line.slice(0, tab);
        if (!/^\d+$/.test(id))
            continue;
        const preview = line.slice(tab + 1);
        const img = IMAGE.exec(preview);
        const meta = META.exec(preview);
        const unit = meta ? UNITS[meta[2]] : undefined;
        out.push({
            line: line,
            id: id,
            preview: preview,
            image: img !== null,
            binary: BINARY.test(preview),
            ext: img ? img[1].toLowerCase().replace("jpg", "jpeg") : "",
            // cliphist's own type word: an image format, an old-style MIME
            // type, or "text" for everything it did not call binary data.
            type: meta ? meta[3] : "text",
            // Verbatim size from cliphist, and the same value in bytes.
            // cliphist rounds to whole units, so `bytes` is an estimate
            // (-1 when the line carries no size at all).
            size: meta ? meta[1] + " " + meta[2] : "",
            bytes: meta && unit !== undefined ? Math.round(parseFloat(meta[1]) * unit) : -1,
            width: meta && meta[4] ? parseInt(meta[4], 10) : 0,
            height: meta && meta[5] ? parseInt(meta[5], 10) : 0
        });
    }
    return out;
}

// Case-insensitive substring match on the preview; every word must match.
function filter(entries, query) {
    const words = String(query || "").toLowerCase().split(/\s+/).filter(w => w !== "");
    if (words.length === 0)
        return entries;
    return entries.filter(e => {
        const p = e.preview.toLowerCase();
        return words.every(w => p.indexOf(w) >= 0);
    });
}

// Byte count in cliphist's units, so the pane and the list agree.
function humanSize(bytes) {
    if (typeof bytes !== "number" || !isFinite(bytes) || bytes < 0)
        return "";
    const units = ["B", "KiB", "MiB", "GiB"];
    let value = bytes;
    let i = 0;
    while (value >= 1024 && i < units.length - 1) {
        value /= 1024;
        i++;
    }
    return Math.round(value) + " " + units[i];
}

// The preview pane's metadata line: type, size, then the pixel size of an
// image or the line count of text. `bytes` is the decoded size once it is
// known (-1 before that), `lines` the decoded line count (0 for an image).
function summary(entry, bytes, lines) {
    if (!entry)
        return "";
    const parts = [entry.type || "text"];
    const size = typeof bytes === "number" && bytes >= 0 ? humanSize(bytes) : entry.size;
    if (size !== "")
        parts.push(size);
    if (entry.width > 0 && entry.height > 0)
        parts.push(entry.width + "\u00d7" + entry.height);
    else if (typeof lines === "number" && lines > 0)
        parts.push(lines + (lines === 1 ? " line" : " lines"));
    return parts.join(" \u00b7 ");
}

// "" when the entry may be decoded, otherwise why it may not be (resource
// rule, architecture 6). `cliphist list` already carries the size and the
// pixel size, so an oversized screenshot is refused from the list line alone
// and is never read into the process. The pixel guard is the one that bounds
// RSS: Qt decodes a PNG in full before it scales it down, so 50 MB of PNG
// would be hundreds of MiB of pixmap.
function tooLarge(entry, maxBytes, maxPixels) {
    if (!entry)
        return "";
    if (maxBytes > 0 && entry.bytes >= 0 && entry.bytes > maxBytes)
        return (entry.size !== "" ? entry.size : humanSize(entry.bytes)) + ", over the " + humanSize(maxBytes) + " preview limit";
    const pixels = entry.width * entry.height;
    if (maxPixels > 0 && pixels > maxPixels)
        return entry.width + "\u00d7" + entry.height + ", over the " + (Math.round(maxPixels / 100000) / 10) + " MP preview limit";
    return "";
}
