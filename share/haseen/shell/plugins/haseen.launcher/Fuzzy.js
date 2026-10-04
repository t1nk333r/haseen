.pragma library

// Fuzzy match score of query q against text s (both lowercased by the
// caller). Higher is better; -1 = no match. Exact > prefix > word start >
// substring > in-order subsequence (tighter subsequences score higher).
function score(q, s) {
    if (!s)
        return -1;
    if (s === q)
        return 1000;
    if (s.startsWith(q))
        return 800 - Math.min(s.length - q.length, 100);
    const at = s.indexOf(q);
    if (at > 0) {
        const before = s.charAt(at - 1);
        if (before === " " || before === "-" || before === "_" || before === ".")
            return 600 - Math.min(at, 100);
        return 400 - Math.min(at, 100);
    }
    let gaps = 0, last = -1;
    for (let i = 0; i < q.length; i++) {
        const j = s.indexOf(q.charAt(i), last + 1);
        if (j < 0)
            return -1;
        if (last >= 0)
            gaps += j - last - 1;
        last = j;
    }
    return Math.max(1, 200 - gaps * 4);
}

// Best score of an app over name, generic name and keywords.
function entryScore(q, entry) {
    let best = score(q, (entry.name || "").toLowerCase());
    const generic = score(q, (entry.genericName || "").toLowerCase());
    if (generic >= 0)
        best = Math.max(best, Math.round(generic * 0.8));
    const keywords = entry.keywords || [];
    for (let i = 0; i < keywords.length; i++) {
        const k = score(q, String(keywords[i]).toLowerCase());
        if (k >= 0)
            best = Math.max(best, Math.round(k * 0.6));
    }
    return best;
}
