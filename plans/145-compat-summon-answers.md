# Plan 145: omarchy-shell's summon carries the payload and says when nothing opened

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW. `omarchy-shell shell summon|toggle` changes only for ids
  that are not `haseen.*` panels; those now reach the plugin with their
  payload, and fail where they used to answer `ok` for nothing.
- **Depends on**: 093 (adopt Omarchy's commands), 096 (the browser picker)
- **Category**: compat
- **Planned at**: 2026-10-30 (owner, "the browser takes long time to
  activate ... via the browser picker plugin")
- **State**: DONE 2026-10-30 (`tests/test-omarchy-commands.sh` 189/189,
  184/189 with the old `omarchy-shell`; `tests/test-compat-runtime.sh` 35/35;
  review round 1, DeepSeek V4.1 Flash, approved ff52d06 with five nits, each
  answered here, §5.5 for the throwing `open`; round 2 approved 211ac8c with
  three wording nits, fixed)

## Problem

On luna every link took about five minutes to open. luna's default browser
was still the Omarchy plugin's own desktop entry,
`t1nk33r-browser-picker.desktop` (`xdg-settings get default-web-browser`),
not haseen's `haseen-browser-picker.desktop` (plan 096). The journal for two
links opened on 2026-10-30:

```
21:48:55 systemd[1350]: Started browser-picker.
21:48:55 env[2723423]: WARN qml: haseen: compat: overlay provider unavailable for 't1nk33r.browser-picker'; ...
21:54:05 app-Hyprland-browser\x2dpicker-29fbed1b.scope: Consumed 6.075s CPU time over 5min 9.759s wall clock time
21:54:09 app-Hyprland-browser\x2dpicker-a416deaa.scope: Consumed 6.079s CPU time over 5min 7.748s wall clock time
```

The plugin's script (`bin/browser-picker` in the owner's plugin, read-only to
haseen) runs `omarchy-shell shell summon t1nk33r.browser-picker <payload>`
(line 104), where the payload names its selection file and its done file, and
falls back to fzf only when that call fails. Otherwise it polls for the done
file every 20 ms, up to 15000 times (lines 115-117): five minutes, and 6 s
of CPU.

The call never failed and never reached the plugin:

- `omarchy-shell` turned every `shell summon|toggle <id> <payload>` into
  `ask panel toggle <id>` and answered `ok` (line 129 before this change). The
  payload was dropped, and so were the selection and done files.
- `panel.toggle(id)` returns nothing (`shell.qml:318`) and hands a compat
  plugin `Compat.Runtime.toggle(key, "")` (`shell.qml:325`), an empty payload.
- The plugin's overlay was not loaded at all. A compat overlay is hosted only
  when its plugin is in a bar section or in `services`
  (`Haseen/Plugins.qml:86-95`), and this one is in neither, so
  `Runtime.summon` stopped at `unsupported("overlay provider", id)`
  (`Compat/Runtime.qml:395`). That is the log line above. `Runtime.summon`
  answered false, and nothing passed the answer on.

Any Omarchy plugin that waits on its own summon hangs the same way.

## What changed

- `shell.qml:343`: an IPC target `compat` with `summon(id, payload)` and
  `toggle(id, payload)`, both strings. They call `Compat.Runtime.summon` and
  `Compat.Runtime.toggle` with the payload and answer `ok` when something
  opened or closed, else `unavailable: <id>`. Why is in the shell's log, which
  `Runtime.unsupported` already writes; a plugin's `open` that returns false
  (`Runtime.qml:364`) and a legacy role id with no provider
  (`Runtime.qml:382`) answer `unavailable` without a line. A plugin whose
  `open` throws (`Runtime.openProvider` calls it directly) leaves the answer
  empty: qs 0.3.2 logs the error, prints nothing and exits 0. That is not
  `ok` either, so `omarchy-shell` still fails.
- `omarchy-shell` (`share/haseen/omarchy/bin/omarchy-shell:131-143`): an id
  that resolves to a `haseen.*` panel still goes to `panel toggle` (lines
  133-136). Any other id goes to `compat <summon|toggle> <id> <payload>`
  (line 141), and an answer other than `ok` fails with "haseen's shell cannot
  open <id>", exit 1 (`-q` still never fails). The old picker now falls back
  at once instead of after five minutes, and a hosted compat overlay receives
  its request. Omarchy built-ins haseen has no plugin for (`omarchy.X`
  without `haseen.X`) reach `Runtime.resolve`, which maps the legacy role
  ids.
- `docs/architecture.md` §5.5 and `haseen shell ipc --help` list the target.
- On luna the owner's default browser is now haseen's picker:
  `haseen setup default browser browser-picker`, 2026-10-30. Its `pick` IPC
  answered in 15-22 ms (three calls with a missing request file, so no card
  opened). Neither picker had routing rules (`rules: []` in both
  `browser-picker.json` files), so none were lost.

## The owner's other callers

Of the owner's Omarchy plugins, two summon through `omarchy-shell`:

- `t1nk33r.browser-picker` (`bin/browser-picker:104`): the bug above. It now
  falls back to fzf at once.
- `t1nk33r.screen-search` (`bin/screen-search:37`), when `resultUi` is `osd`,
  its manifest default and luna's value. On luna it sits in a bar section, so
  its overlay is hosted: SUPER + CTRL + PRINT and SUPER + SHIFT + PRINT now
  hand it `{mode: "ocr"|"circle"}` instead of an empty payload, and a summon
  no longer closes a card that is open. Outside the bar and `services` its
  overlay is not hosted, and the script, under `set -e` with no `||`, now
  exits 1 where it used to exit 0 having done nothing.

## Known limits

- A `haseen.*` id still goes to `panel toggle`, which returns nothing, so a
  disabled built-in (`omarchy.updates` → `haseen.updates`, off by default)
  still answers `ok` for a panel that did not open. Unchanged by this plan;
  a caller waiting on one would wait as before.
- No test calls the new handler through a real `qs` (the real `shell.qml`
  needs a Wayland backend). Review round 1 probed the contract by hand on qs
  0.3.2 with an `IpcHandler` of the same signature: an empty payload arrives
  as `""`, one argument is "Too few arguments provided", which `ask` catches.

## Under DMS

`ipc-translate` has no mapping for `compat` and exits 3, so a compat summon
under DMS fails at once, as it should, though `omarchy-shell` words it as
"haseen's shell is not running". `haseen.*` panels keep `panel toggle`, which
it does translate for the launcher, notifications and session.

## Tests

- `tests/test-omarchy-commands.sh`: the fake IPC records its calls and
  answers `compat` from `$IPC_COMPAT`. A `haseen.*` panel is a `panel toggle`;
  a compat summon carries its payload, a toggle stays a toggle, an `omarchy.X`
  without a haseen plugin goes to the compat host, `unavailable` exits 1 and
  names the plugin, `-q` stays silent and 0, and no shell still fails as not
  running. 189/189; with the old `omarchy-shell`, 184/189 (the payload, toggle,
  `omarchy.X`, failure and message checks fail).
- `tests/test-compat-runtime.sh`, in the real Quickshell engine: `summon`
  answers true when it opened the hosted overlay, and false for `me.unhosted`,
  an enabled Omarchy overlay plugin in no bar section, which is luna's case.
  35/35.
- The real `shell.qml` cannot start offscreen ("No PanelWindow backend
  loaded"), so the `compat` handler itself is checked by qmllint, not by a
  real-engine call. The two sides it joins are tested above.

## Rejected options

- **Make `panel toggle` take a payload or return a string.** QML IPC
  functions cannot be overloaded by argument count, and the binds,
  `ipc-translate` (`panel toggle` with exactly one argument) and wrappers
  such as `omarchy-menu-emoji`, which prints what `haseen shell ipc` prints,
  all call `toggle(id)`.
- **Send `haseen.*` panels through `compat` too.** `ipc-translate` maps
  `panel toggle` for the launcher, notifications and session under DMS; a
  `compat` call would lose that.
- **Host every enabled compat overlay, not only those in the bar.** That
  loads plugins the bar does not show and is a change to architecture §6's
  lazy loading; it is the owner's call, and haseen's own picker replaces this
  plugin.
- **Switch the default browser from the Omarchy picker to haseen's
  automatically.** Plan 096 rejected making the picker the default without
  the owner, and haseen does not edit the user's files after seeding them.
- **Shorten the plugin's 5-minute poll.** The plugin is the owner's, under
  `~/.config/omarchy/plugins/`, which haseen never edits.
