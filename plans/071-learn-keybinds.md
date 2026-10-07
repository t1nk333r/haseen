# Plan 071: Learn › Keybindings and Learn › Tmux as Omarchy's searchable lists

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (two new list commands, a pick-list mode of the menu card that is off until a caller asks for it, and better key names in the keybind sheet's records)
- **Depends on**: 030 068
- **Category**: shell, menu
- **Planned at**: 2026-10-07, owner report (io): "Learn › Tmux and Keybindings are not displayed well."
- **State**: DONE 2026-10-07 (`tests/test-keybinds.sh`, `tests/test-learn-keys.sh`, `tests/test-menu.sh`; nested-session frames in `~/.cache/haseen-wt/LearnKeys/shots/`)

## What was wrong

Plan 068 brought Learn back with two rows that Omarchy 4 runs as searchable
lists (`/usr/bin/omarchy-menu-keybindings`, `/usr/bin/omarchy-menu-tmux-keybindings`,
both shown through `omarchy-menu-select 'Keybindings' -- --width 800 --height 500`):

- `learn.keybindings` toggled the SUPER + / sheet (`haseen.keybinds`). Its
  records came from `hyprctl binds -j`, and Hyprland 0.56 reports every Lua
  bind as dispatcher `__lua` with a function id, a `code:N` bind with an empty
  key, and mouse buttons by number. On io, `/usr/local/bin/haseen keybinds
  --json` gave 35 of 148 binds with an empty or raw key: the workspace binds
  read `SHIFT + SUPER + ` with no key, the window drag `SUPER + mouse:272`,
  and every Lua bind had no action. 65 binds fell under "Other", because the
  sections came from `b("KEY", "Description")` lines only, and binds made in
  a loop (workspaces, directions) have no literal description.
- `learn.tmux-keybindings` opened `tmux start-server \; list-keys -N | less`
  in a terminal: a pager of the default server's notes, no copy mode, raw
  key names.

Omarchy's own tmux script does not work on io either: with the owner's
`~/.config/tmux/tmux.conf` it prints `PREFIX → ` (empty) and
`'~/.CONFIG/TMUX/TPM/TPM' + RETURNED → 127` as a key. Two causes, both shown
in a throwaway server on its own socket:
- `source-file` inside one command chain queues the file's commands after
  the rest of the chain, so `show-options -g prefix` and `list-keys` run
  before the config;
- tmux 3.7c lists nothing for `list-keys -T root` (and `-T copy-mode-vi`)
  once that table was emptied with `unbind-key -a`, even after new binds; the
  plain listing and `list-keys -F` still show them. `C--` was also split on
  every dash (`CTRL +  +`).

## Change

- **`share/haseen/lib/keybinds-scan.lua`** (port of Omarchy's
  `build_lua_bind_cache`): runs the Lua config
  (`$XDG_CONFIG_HOME/hypr/hyprland.lua`, else `default/hypr/init.lua`) under a
  stub `hl` and prints every described bind as
  `modmask, description, key, kind, arg, section`. `hl.dsp.exec_cmd("…")`
  becomes `exec`, any other `hl.dsp.…(…)` a `lua` expression `hyprctl dispatch`
  accepts, a Lua function `""`. `hl.unbind` drops what it unbinds
  (`haseen.rebind`). The section is the `-- Name -----` comment above the
  bind's call site (the first main chunk up the stack), so a bind made in a
  loop gets the section of the loop.
- **`bin/haseen-keybinds`** (the sheet's data, plan 030) now resolves:
  - a key reported as `MODS + code:N` loses the modifiers; an empty key with a
    keycode becomes `code:N`; an empty key without one comes from the scan by
    modmask and description;
  - `code:N` is named through `xkbcli compile-keymap` (the number row and
    `- = , . /` as a fallback), `mouse:272..276` and `mouse_up/down/left/right`
    are named, lower-case names (`comma`) read in capitals;
  - modifiers in binds.lua's order: SUPER, SHIFT, CTRL, ALT;
  - each `__lua` bind's dispatcher and argument from the scan, as new record
    fields `dispatcher` and `arg`; `action` shows the command without the
    `uwsm-app --` wrapper;
  - the category is the scan's section first, then the old description match.
  On io's 148 live binds (the installed tree plus the new scan): 0 empty or
  raw keys (was 35), and "Other" holds 19 (was 65), all the owner's own binds
  in `~/.config/hypr/bindings.lua` written under no section comment. The
  sheet's QML is unchanged.
- **`bin/haseen-keybinds-list [--print] [--dry-run]`** (`haseen keybinds
  list`, port of `omarchy-menu-keybindings`): rows `KEYS → description`
  (combo padded to 35, as Omarchy's `%-35s`), Omarchy's priority order on
  haseen's descriptions (Keybindings, Menu, Terminal, Browser, … workspaces,
  XF86 keys last), one row per label. `--print` prints them. Otherwise
  `haseen menu select Keybindings --width 800 --height 500`, and Enter
  replays the bind like Omarchy's `dispatch_binding`: `exec` through
  `hyprctl dispatch 'hl.dsp.exec_cmd("…")'` (falling back to `dispatch exec`),
  `lua` through `hyprctl dispatch '<expression>'`, a native dispatcher as
  itself. A Lua-function bind (the universal clipboard keys, the snap keys)
  cannot be replayed: it warns and exits 1. `--dry-run` prints the dispatch.
- **`bin/haseen-tmux-keybinds [--print] [--config PATH]`** (`haseen tmux
  keybinds`, port of `omarchy-menu-tmux-keybindings`): a throwaway server on a
  socket in a temp dir, kept up by a detached `cat` session, and each tmux
  command a separate call so the config is in place before the listing.
  `list-keys -F '#{key_table}…#{key_note}…#{key_command}'` reads all tables.
  The rows are tmux's real bindings (its defaults too, unless the config
  unbinds them): `PREFIX → C-a / C-b` first, then `PREFIX + KEY`, root keys
  bare, then `COPY MODE + KEY` for the table `mode-keys` picks; the note, else
  the command. Mouse events are left out. A config error (a missing plugin
  manager) leaves the rest bound. The config is `--config`, `$TMUX_CONF`,
  `~/.config/tmux/tmux.conf`, then `~/.tmux.conf`; with none, tmux's own
  keys. Shown 800 wide and 40% of the focused monitor high, as Omarchy does;
  choosing a row closes the list, as in Omarchy.
- **`bin/haseen-menu-select <prompt> [option...] [--width N] [--height N]`**
  (`haseen menu select`, port of `omarchy-menu-select`). haseen had no
  graphical picker (the terminal ones use fzf, `bin/haseen-drive-select`), so
  the menu card gets Omarchy's dmenu mode:
  - the options (arguments or stdin; Omarchy's `glyph<TAB>label<TAB>detail`)
    go in a request file in a private `$XDG_RUNTIME_DIR/haseen-select.*` dir,
    so any length fits;
  - IPC `menu select(request)` (`shell.qml`) calls the panel's `pick()`,
    opening the menu first when it is closed, and answers the shell's PID;
  - `Panel.qml`: `picking` swaps the rows for `MenuModel.pickRows(options,
    query)` (every query word must be in the label or the detail, the given
    order kept), the header reads the prompt, the card takes the request's
    width and caps the rows at its height; Enter writes the row (with its
    detail) and closes; Escape, a click outside, another menu path or the
    panel going away answer "nothing chosen";
  - the answer is one line on a FIFO the caller opened read-write, so the
    caller waits without polling, and neither side blocks if the other is
    gone. Every 2 s without an answer the caller checks the shell's PID and
    gives up if it died.
- `share/haseen/default/menu.jsonc`: `learn.keybindings` runs `haseen
  keybinds list` (alias `keybinds` kept), `learn.tmux-keybindings` runs
  `haseen tmux keybinds`.
- The SUPER + / sheet stays as it was; its records gained the names above.

## Evidence

- Tests: `tests/test-keybinds.sh` (stubbed `hyprctl -j binds` fixture with
  `code:N` binds Hyprland reports empty or as `MODS + code:N`, a keymap
  keycode through a stub `xkbcli`, a mouse button, a lower-case key, a
  Lua-function bind, a native bind, an undescribed `__lua` bind, an unbound
  key, sections above a loop; `haseen keybinds list --print`; the picker's
  arguments and input; Enter on Lua, exec and native binds; `--dry-run`;
  closing the list). `tests/test-learn-keys.sh` (real tmux 3.7c on a sandbox
  socket: prefix and prefix2, notes, `C--`, root keys after `unbind -a -T
  root`, `M-S-Enter`, copy-mode-vi only, no mouse rows, no row twice, the
  server gone, default config lookup, a missing config, the picker's size;
  `haseen menu select` against a stubbed shell: stdin options, `-- --width
  --height`, the chosen line, nothing chosen, no options, a dead shell).
  `tests/test-menu.sh` (the Learn actions; `pickRows` filtering and order
  under node).
- Nested session (theme `haseen`, the shipped binds loaded into the nested
  Hyprland, Omarchy's `tmux.conf` as the user's), in
  `~/.cache/haseen-wt/LearnKeys/shots/`:
  - `keybinds.png`: Learn › Keybindings, 800 px, `SUPER + SLASH → Keybindings`
    first;
  - `keybinds-search.png`: "workspace 3" leaves the three workspace-3 binds
    with resolved keys; Enter then switched the nested Hyprland to workspace 3
    (`hyprctl activeworkspace` 1 → 3), and `--dry-run` printed
    `DRYRUN: hyprctl dispatch hl.dsp.focus({ workspace = "3" })`;
  - `tmux.png`, `tmux-search.png` ("split"): Learn › Tmux;
  - `overlay.png`, `overlay-search.png`: the SUPER + / sheet with sections
    (Ambient, Apps, Capture, Clipboard, …) and named workspace keys.
  - Closing the panel from outside (`panel close`) ended a waiting
    `haseen keybinds list` with status 0.

## Rejected

- **Keep the sheet for Learn › Keybindings.** It is a different view (all
  binds by section, no running); Omarchy's row is a list you run from, and
  SUPER + / still opens the sheet.
- **fzf in a floating terminal as the picker.** haseen's terminal pickers use
  it, but the owner asked for Omarchy's look; the menu card already is
  Omarchy's.
- **Omarchy's `unbind -a` then `source-file` in one chain for tmux.** It
  lists before the config loads and hits tmux 3.7's empty `-T root` listing;
  it also hid tmux's default keys, which still work in the real server.
- **Parsing `hyprctl binds` text as Omarchy does.** Omarchy avoids `-j`
  because Hyprland 0.56.0 emitted invalid JSON; io's 0.56.2 emits valid JSON
  (`hyprctl -j binds | jq length` = 148) and the sheet already reads it.
- **Replaying Lua-function binds** by synthesising key presses: it would
  send input to whatever is focused. They are listed, and Enter says why
  nothing runs.
