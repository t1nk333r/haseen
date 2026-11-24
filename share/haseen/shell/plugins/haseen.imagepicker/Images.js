.pragma library

// Image list logic for haseen.imagepicker. Adapted from Omarchy
// shell/plugins/image-picker/ImagePickerModel.js (MIT, Copyright (c) David
// Heinemeier Hansson): the name/label derivation and the de-duplication of
// the scanned rows. Pure, so tests run it headless.

// The extensions the scan asks `find` for, and that Qt's image plugins read.
const EXTENSIONS = ["jpg", "jpeg", "png", "webp", "gif", "bmp", "avif"];
// The ones the default action takes: `haseen theme bg set` refuses anything
// but PNG, JPEG, WebP, GIF and BMP (bin/haseen-theme-bg image_ok), and the
// panel has closed by the time it fails, so an AVIF pick did nothing and
// said nothing (plan 197).
const BACKGROUND_EXTENSIONS = ["jpg", "jpeg", "png", "webp", "gif", "bmp"];

// What the scan lists: every image for a configured command, only what the
// background takes for the default one.
function extensionsFor(customCommand) {
    return customCommand ? EXTENSIONS : BACKGROUND_EXTENSIONS;
}

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
