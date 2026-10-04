.pragma library

// `cliphist list` output -> rows for the clipboard panel and launcher
// provider. Pure functions (tests/test-widgets-b.sh runs them).
//
// cliphist prints one `<id>\t<preview>` line per entry, newest first; binary
// entries preview as `[[ binary data 12 KiB png 640x480 ]]`.

const IMAGE = /^\[\[ binary data .*?\b(png|jpe?g|gif|bmp|webp)\b.*\]\]$/i;
const BINARY = /^\[\[ binary data .*\]\]$/;

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
        out.push({
            line: line,
            id: id,
            preview: preview,
            image: img !== null,
            binary: BINARY.test(preview),
            ext: img ? img[1].toLowerCase().replace("jpg", "jpeg") : ""
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
