.pragma library

// Pure parsers for the greeter, so tests/test-greeter.sh can run them headless
// under /usr/lib/qt6/bin/qml. Rules adapted from DankMaterialShell
// quickshell/Services/GreeterUsersService.qml and GreeterContent.qml (MIT,
// Copyright (c) 2025 Avenge Media LLC).

// getent passwd -> [{name, display}] for the humans on this machine: uid
// 1000-59999, not nobody, a login shell, a real home.
function parseUsers(text) {
    const out = [];
    for (const line of String(text || "").split("\n")) {
        const f = line.split(":");
        if (f.length < 7)
            continue;
        const uid = Number(f[2]);
        if (!(uid >= 1000 && uid < 60000))
            continue;
        if (f[0] === "nobody" || /(nologin|false)$/.test(f[6]) || f[5] === "/var/empty")
            continue;
        const gecos = String(f[4] || "").split(",")[0];
        out.push({
            name: f[0],
            display: gecos || f[0]
        });
    }
    out.sort((a, b) => a.name.localeCompare(b.name));
    return out;
}

// One .desktop session entry -> {id, name, exec}, or null when it has no Exec
// or says Hidden/NoDisplay. `id` is the file name without .desktop, which is
// what the session is remembered by.
function parseSession(id, text) {
    let name = "";
    let exec = "";
    let hidden = false;
    let inEntry = false;
    for (const raw of String(text || "").split("\n")) {
        const line = raw.trim();
        if (line.startsWith("[")) {
            inEntry = line === "[Desktop Entry]";
            continue;
        }
        if (!inEntry)
            continue;
        if (line.startsWith("Name=") && !name)
            name = line.slice(5);
        else if (line.startsWith("Exec=") && !exec)
            exec = line.slice(5);
        else if (/^(Hidden|NoDisplay)=true$/i.test(line))
            hidden = true;
    }
    if (!exec || hidden)
        return null;
    return {
        id: id,
        name: name || id,
        exec: exec
    };
}

// `find`-style listing (one path per line) -> sessions, Wayland first, each id
// once: a session installed in /usr/local shadows the one in /usr.
function parseSessions(entries) {
    const seen = {};
    const out = [];
    for (const entry of entries || []) {
        if (!entry || !entry.id || seen[entry.id])
            continue;
        seen[entry.id] = true;
        out.push(entry);
    }
    return out;
}

// greetd takes an argv, not a shell string. A desktop Exec may carry field
// codes (%f, %U, …) and quotes; drop the codes, split on spaces outside quotes.
function commandFor(exec) {
    const cleaned = String(exec || "").replace(/%[fFuUdDnNickvm]/g, " ").trim();
    const argv = [];
    let current = "";
    let quote = "";
    for (const ch of cleaned) {
        if (quote) {
            if (ch === quote)
                quote = "";
            else
                current += ch;
        } else if (ch === '"' || ch === "'") {
            quote = ch;
        } else if (ch === " ") {
            if (current) {
                argv.push(current);
                current = "";
            }
        } else {
            current += ch;
        }
    }
    if (current)
        argv.push(current);
    return argv;
}

// What the greeter remembers between logins: the last user and the session
// each user picked. Unknown shapes read as empty, never as an exception.
function readMemory(text) {
    let data = {};
    try {
        data = JSON.parse(String(text || "{}"));
    } catch (e) {
        data = {};
    }
    return {
        lastUser: typeof data.lastUser === "string" ? data.lastUser : "",
        sessions: data.sessions && typeof data.sessions === "object" ? data.sessions : {}
    };
}

function withMemory(memory, user, sessionId) {
    const sessions = Object.assign({}, memory.sessions);
    if (user && sessionId)
        sessions[user] = sessionId;
    return {
        lastUser: user || memory.lastUser,
        sessions: sessions
    };
}
