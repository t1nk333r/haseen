.pragma library

// Image list logic for haseen.imagepicker. Adapted from Omarchy
// shell/plugins/image-picker/ImagePickerModel.js (MIT, Copyright (c) David
// Heinemeier Hansson): the name/label derivation and the de-duplication of
// the scanned rows. Pure, so tests run it headless.

// The extensions the scan asks `find` for, and that Qt's image plugins read.
const EXTENSIONS = ["jpg", "jpeg", "png", "webp", "gif", "bmp", "avif"];

// "~/Pictures" and "$HOME/Pictures" name the same directory as the CLI does.
function expandHome(path, home) {
    const value = String(path || "").trim();
    if (value === "")
        return "";
    if (value === "~" || value === "$HOME")
        return String(home || "");
    if (value.startsWith("~/"))
        return String(home || "") + value.slice(1);
    if (value.startsWith("$HOME/"))
        return String(home || "") + value.slice(5);
    return value;
}

// Absolute, duplicate-free directory list for the scan.
function directories(values, home) {
    const dirs = [];
    const seen = {};
    for (const value of Array.isArray(values) ? values : []) {
        const dir = expandHome(value, home);
        if (dir === "" || !dir.startsWith("/") || seen[dir])
            continue;
        seen[dir] = true;
        dirs.push(dir);
    }
    return dirs;
}

function nameFor(path) {
    return String(path || "").split("/").pop().replace(/\.[^/.]+$/, "");
}

function labelFor(path) {
    return nameFor(path).replace(/[-_]+/g, " ").replace(/\b\w/g, c => c.toUpperCase());
}

// One path per line from the scan; the first of two files with the same name
// wins, so a directory listed earlier shadows the later copies.
function parseList(text) {
    const images = [];
    const seen = {};
    for (const line of String(text || "").split("\n")) {
        const path = line.trim();
        if (path === "" || !path.startsWith("/"))
            continue;
        const file = path.split("/").pop();
        if (seen[file])
            continue;
        seen[file] = true;
        images.push({
            path: path,
            file: file,
            label: labelFor(path)
        });
    }
    images.sort((a, b) => a.label.localeCompare(b.label));
    return images;
}

// Every word of the query must appear in the label or the path, any case.
function filter(images, query) {
    const words = String(query || "").toLowerCase().split(/\s+/).filter(w => w !== "");
    if (words.length === 0)
        return Array.isArray(images) ? images : [];
    return (Array.isArray(images) ? images : []).filter(image => {
        const haystack = (image.label + " " + image.path).toLowerCase();
        return words.every(word => haystack.indexOf(word) !== -1);
    });
}
