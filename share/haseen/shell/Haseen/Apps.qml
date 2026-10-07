pragma Singleton

import QtQuick
import Quickshell

// Apps (plan 074): the one way the shell starts a user-facing app. Anything
// qs spawns lands in haseen-shell.service's cgroup, and the unit's
// KillMode=control-group kills it on every shell restart. Worse, an app that
// moves itself into its own scope (Chromium, Helium) leaves its stdout/stderr
// readers behind there, so a restart breaks its pipes and it crashes.
//
// launch() starts the command in its own systemd scope instead, as
// Hyprland's haseen.launch does (default/hypr/init.lua):
//   1. `uwsm-app -- argv` when uwsm-app is on PATH and uwsm runs the session
//      (it exports UWSM_FINALIZE_VARNAMES / UWSM_WAIT_VARNAMES);
//   2. else `systemd-run --user --scope` into app-graphical.slice, named like
//      uwsm's units: app-haseen-<id>-<random>.scope;
//   3. else the plain command.
// The choice is made by a short sh at spawn time, which execs the chosen
// tool, so nothing of the app stays in the shell's cgroup.
// Helpers the shell runs for itself (qs ipc, wl-copy, haseen CLI writes)
// stay on Quickshell.execDetached.
Singleton {
    id: root

    readonly property string picker: 'id=$1 unit=$2 dir=$3; shift 3
[ -n "$dir" ] && cd -- "$dir" 2>/dev/null
if [ -n "${UWSM_FINALIZE_VARNAMES-}${UWSM_WAIT_VARNAMES-}" ] && command -v uwsm-app >/dev/null 2>&1; then
    if [ -n "$id" ]; then exec uwsm-app -a "$id" -- "$@"; fi
    exec uwsm-app -- "$@"
fi
if command -v systemd-run >/dev/null 2>&1; then
    exec systemd-run --user --scope --slice=app-graphical.slice --collect --quiet --unit="$unit" -- "$@"
fi
exec "$@"'

    // The unit-name part for an app: the desktop id without ".desktop", or
    // the command's basename; anything outside [A-Za-z0-9_.] becomes "_".
    function unitId(command: var, desktopId: string): string {
        let base = String(desktopId || "").replace(/\.desktop$/, "");
        if (base === "")
            base = String(command[0] || "app").replace(/^.*\//, "");
        return base.replace(/[^A-Za-z0-9_.]/g, "_") || "app";
    }

    function unitName(command: var, desktopId: string): string {
        const rand = Math.floor(Math.random() * 0x100000000).toString(16).padStart(8, "0");
        return "app-haseen-" + unitId(command, desktopId) + "-" + rand + ".scope";
    }

    // The argv execDetached gets for launch(command, opts).
    function argv(command: var, opts: var): var {
        const o = opts || {};
        const id = String(o.desktopId || "").replace(/\.desktop$/, "");
        return ["sh", "-c", picker, "haseen-app", id, unitName(command, id), String(o.workingDirectory || "")].concat(command.map(String));
    }

    // launch(["foot"]), launch(argv, {desktopId, workingDirectory})
    function launch(command: var, opts: var): void {
        if (!command || command.length === 0)
            return;
        Quickshell.execDetached(argv(command, opts));
    }

    // A desktop entry's Exec without its field codes (Desktop Entry spec:
    // the shell opens no files or URLs, so %f %F %u %U and the deprecated
    // codes go; %i %c %k too; %% is a literal %).
    function stripFieldCodes(command: var): var {
        const out = [];
        for (const arg of command) {
            const s = String(arg);
            if (/^%[fFuUdDnNvmick]$/.test(s))
                continue;
            out.push(s.replace(/%([fFuUdDnNvmick%])/g, (m, c) => c === "%" ? "%" : ""));
        }
        return out;
    }

    // What launchEntry runs: the Exec argv, inside $TERMINAL (foot when
    // unset, as SUPER+RETURN) for Terminal=true entries.
    function entryCommand(entry: var): var {
        const command = stripFieldCodes(entry.command || []);
        if (!entry.runInTerminal || command.length === 0)
            return command;
        return ["sh", "-c", 'exec "${TERMINAL:-foot}" -e "$@"', "sh"].concat(command);
    }

    function launchEntry(entry: var): void {
        if (!entry)
            return;
        launch(entryCommand(entry), {
            desktopId: entry.id,
            workingDirectory: entry.workingDirectory
        });
    }
}
