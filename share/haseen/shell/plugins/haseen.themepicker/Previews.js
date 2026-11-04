.pragma library

// Which image the theme picker shows for each theme. Adapted from Omarchy's
// bin/omarchy-theme-switcher (find_preview: a theme's preview, else its
// first background, the user's copy before Omarchy's).
// MIT, Copyright (c) David Heinemeier Hansson.
// haseen looks in three places instead of two, and puts Omarchy's stock
// previews before any stock background (plan 158). It uses no Qt types, so
// tests/test-carousel.sh runs it without a window.

// The names Omarchy looks for, in its order. It matches them in any case.
const PREVIEWS = ["preview.png", "preview.jpg", "preview.jpeg", "preview.webp", "preview.gif", "preview.bmp"];
const IMAGE = /\.(jpe?g|png|gif|bmp|webp)$/i;

// Each place a theme's image can come from, best first. The user's theme
// comes first, as in Omarchy. The fetched cache and the Omarchy install hold
// the same stock themes: the cache matches the commit haseen's stock colours
// come from, and any stock preview is a better picture of a theme than a
// stock background.
const TIER = {
    userPreview: 0,
    userBackground: 1,
    cachePreview: 2,
    omarchyPreview: 3,
    cacheBackground: 4,
    omarchyBackground: 5
};

// Reads find's output, one path per line, under the three roots in
// `roots` ({user, cache, omarchy}). Returns {previews, colours}:
// previews maps a theme name to the path of its best image, and colours
// lists the user themes that have their own colors.toml.
function index(text, roots) {
    const best = {};
    const colours = {};
    const places = [["user", roots.user], ["cache", roots.cache], ["omarchy", roots.omarchy]];
    for (const path of text.split("\n")) {
        const place = places.find(p => p[1] && path.startsWith(p[1] + "/"));
        if (!place)
            continue;
        const parts = path.slice(place[1].length + 1).split("/");
        const name = parts[0];
        let rank;
        if (parts.length === 2) {
            if (parts[1] === "colors.toml") {
                if (place[0] === "user")
                    colours[name] = true;
                continue;
            }
            const which = PREVIEWS.indexOf(parts[1].toLowerCase());
            if (which < 0)
                continue;
            rank = TIER[place[0] + "Preview"] * 10 + which;
        } else if (parts.length === 3 && parts[1] === "backgrounds" && IMAGE.test(parts[2])) {
            rank = TIER[place[0] + "Background"] * 10;
        } else {
            continue;
        }
        // Omarchy takes the first background in sorted order.
        const had = best[name];
        if (!had || rank < had.rank || (rank === had.rank && path < had.path))
            best[name] = {
                rank: rank,
                path: path
            };
    }
    const previews = {};
    for (const name in best)
        previews[name] = best[name].path;
    return {
        previews: previews,
        colours: colours
    };
}
