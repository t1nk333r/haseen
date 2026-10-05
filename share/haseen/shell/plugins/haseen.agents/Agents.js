.pragma library

// Row logic for haseen.agents: the TSV agents-list.sh prints turned into the
// lines the panel draws. Pure, so tests run it headless.

// "pid \t name \t seconds \t cwd" per line. Longest-running first, so the
// session that has been working all afternoon is at the top.
function parse(text, home) {
    const rows = [];
    for (const line of String(text || "").split("\n")) {
        if (line.trim() === "")
            continue;
        const parts = line.split("\t");
        const pid = parseInt(parts[0], 10);
        const name = String(parts[1] || "").trim();
        if (!(pid > 0) || name === "")
            continue;
        const seconds = parseInt(parts[2], 10);
        const cwd = String(parts[3] || "").trim();
        rows.push({
            pid: pid,
            name: name,
            seconds: seconds > 0 ? seconds : 0,
            cwd: cwd,
            project: project(cwd),
            where: shorten(cwd, home)
        });
    }
    rows.sort((a, b) => b.seconds - a.seconds || a.pid - b.pid);
    return rows;
}

// The directory the agent works in, which is the project as far as the panel
// is concerned.
function project(cwd) {
    const parts = String(cwd || "").split("/").filter(p => p !== "");
    return parts.length > 0 ? parts[parts.length - 1] : "";
}

function shorten(cwd, home) {
    const path = String(cwd || "");
    const base = String(home || "");
    if (base !== "" && (path === base || path.startsWith(base + "/")))
        return "~" + path.slice(base.length);
    return path;
}

// "45s", "12m", "3h 07m", "2d 4h".
function duration(seconds) {
    const total = Math.max(0, Math.round(Number(seconds) || 0));
    if (total < 60)
        return total + "s";
    const minutes = Math.floor(total / 60);
    if (minutes < 60)
        return minutes + "m";
    const hours = Math.floor(minutes / 60);
    if (hours < 24)
        return hours + "h " + ("0" + (minutes % 60)).slice(-2) + "m";
    return Math.floor(hours / 24) + "d " + (hours % 24) + "h";
}

// The line under the title: what is running, in how many projects.
function summary(rows) {
    const list = Array.isArray(rows) ? rows : [];
    if (list.length === 0)
        return "nothing running";
    const projects = {};
    for (const row of list)
        projects[row.cwd || row.pid] = true;
    const count = Object.keys(projects).length;
    return list.length + (list.length === 1 ? " agent · " : " agents · ") + count + (count === 1 ? " project" : " projects");
}
