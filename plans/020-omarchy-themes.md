# Plan 020: All 22 Omarchy themes, fetched backgrounds, theme picker

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM
- **Depends on**: 005 010 011
- **Category**: shell
- **Planned at**: 2026-10-04, owner request (second feature round)
- **State**: DONE 2026-10-04. Omarchy ships 22 stock themes, not 23, and all are present. A real pinned fetch of tokyo-night ran, and the picker was verified live over IPC.

## Why this matters

The owner chose all 23 themes as text, with backgrounds and previews fetched on first use and cached, plus a picker with previews.

## Execution record

### Count: 22, not 23

Omarchy at the pinned commit ships **22** themes (`ls /tmp/ref/omarchy/themes | wc -l` → 22; its
`manual/06-themes.md` says "twenty-two"). haseen already had 5 of them (plan 004), so 17 were added and
the stock set is now exactly Omarchy's 22 (`tests/test-themes2.sh` pins the list).

### What changed

- `share/haseen/themes/<17 new>/`: Omarchy's text files only — `colors.toml icons.theme neovim.lua
  vscode.json btop.theme hyprland.lua` where the theme has them (no `light.mode` exists at the pin;
  `keyboard.rgb` only in tokyo-night). The 5 existing themes are byte-identical to the pin (`cmp`).
  344 KB in total, no images. `kanagawa/hyprland.lua` drops Omarchy's `o.window({ tag = "terminal" }, …)`
  line: haseen has neither the `o` helper nor a `terminal` tag, and Hyprland would fail on the call.
- `share/haseen/layers/theme/omarchy-assets.txt`: 114 rows `sha256 size path` (22 `preview.png` + 92
  backgrounds, 63 750 631 bytes), generated from git objects of omacom/omarchy
  `5c4da021469517449770579793b37ce26d0a0d48` (`git ls-tree -r -l` + `git cat-file blob | sha256sum`), not
  from the worktree.
- `theme-lib.sh`: `THEME_CACHE_DIR` (`$HASEEN_USER_CACHE` or `$XDG_CACHE_HOME/haseen` + `/themes`), the
  pin, `theme_asset_base` (URL `https://raw.githubusercontent.com/omacom/omarchy/<commit>/themes`;
  `HASEEN_THEME_MIRROR` swaps the host for tests), `theme_assets*`, `theme_fetch_in_background`
  (`setsid -f haseen-theme-fetch --quiet`, log `state/theme-fetch.log`; off with `HASEEN_THEME_FETCH=0`
  or headless), `theme_backgrounds` now user dir → `current/theme/backgrounds` → cache (each sorted),
  `theme_set_background_link` (symlink to `current/.background.tmp` then `mv -T`, so FileView watchers
  never see it missing), `theme_background_active` (pure read of systemd's
  `$XDG_RUNTIME_DIR/systemd/units/invocation:haseen-background.service`) and `theme_background_reload`
  (`systemctl --user try-restart`). Also the `haseen font set` hook agreed with Menu:
  `~/.config/haseen/font` overrides `font_mono` and appends a font line to the rendered
  foot/kitty/ghostty/alacritty configs; absent file = output unchanged.
- `bin/haseen-theme-fetch [name] [--all] [--quiet] [--dry-run]`: per image, intact cache hit (size +
  sha256) is kept; otherwise `curl --fail --proto =https --proto-redir =https --max-filesize 8 MiB
  --continue-at -` into a hidden `.x.part`, then `file --mime-type` ∈ png/jpeg/webp, size == manifest,
  sha256 == manifest, `mv`. curl exit 63 deletes the partial; other failures keep it for resume. One
  `flock -n` per theme. When the fetched theme is current and has no background link, the first one
  is linked and the service restarted. With `glycin-thumbnailer` (glycin, a dependency of gdk-pixbuf2
  and so of swaybg) it writes `preview-thumb.png` (512 px) for the picker.
- `bin/haseen-theme-bg <list|current|set FILE|next>` (adapted from omarchy-theme-bg-next/-set): `list`
  prints full paths; `set` takes a listed path, its file name or any image (`file --mime-type`); writes
  under the theme-set lock. Hidden `bin/haseen-theme-bg-run` is the unit's ExecStart: `swaybg --mode fill
  --image <link target>`, or `--color <theme background>` without an image.
- `share/haseen/systemd/user/haseen-background.service`: `PartOf=graphical-session.target`,
  `Conflicts=dms.service` (DMS draws its own wallpaper), `Slice=background-graphical.slice`.
  `install.sh` already installs every unit in that directory.
- `bin/haseen-theme-set`: after post-set (not headless) restarts the background service when it runs
  and starts the detached fetch; dry run prints both.
- `layers/theme/layer.sh`: apply enables `haseen-background.service`; status reports swaybg and the
  enable link; new `layer_remove` disables the unit and keeps theme + cache.
- `share/haseen/shell/plugins/haseen.themepicker/` (`Panel.qml`, `ThemeCard.qml`, manifest; panel,
  permissions `exec files:read`, settings `columns`/`rows`/`debugIpc`): on open one `find` (user themes'
  `colors.toml`/`preview.png`, cached `preview-thumb.png`/`preview.png`), then `haseen theme list`; each
  card gets one existing preview path (user preview → thumb → full) or draws the theme's palette
  (background, "Aa" in its foreground, 8 swatches) from one `FileView` on the colors.toml staging would
  use. Arrows/Tab move (GridView), Enter/click runs `haseen theme set NAME` and closes. Debug IPC
  target `haseen.themepicker`: `select(name)`, `move(dir)`, `accept()`, `state()`.
- Tests: new `tests/test-themes2.sh`; `tests/test-theme.sh` adapted (hex case `[0-9a-fA-F]` since
  ethereal/flexoki-light/hackerman/kanagawa/… use upper case; shipped-neovim check only for themes that
  ship one; the install fixture renamed `nordtest` since `nord` is now stock; `HASEEN_THEME_FETCH=0` and
  a sandbox `XDG_RUNTIME_DIR`; the layer block fakes swaybg and the unit enable).

### Evidence

- `tests/run.sh tests/test-themes2.sh tests/test-theme.sh` → `799/799 passed`. test-themes2 covers: the 22
  render headless with no warnings, no `{{`, §7 keys, Lua parses; the manifest shape/pin/limit; fetch
  against a `file://` mirror at `<mirror>/<pin>/themes/…` with a logging curl stub (dry-run prints the
  upstream `raw.githubusercontent.com/omacom/omarchy/<pin>/…` URLs and runs no curl, every request
  carries the pin, `--proto =file`, `--max-filesize`, `--continue-at -`), idempotency (0 curl calls),
  resume from a 1000-byte `.part` plus repair of a same-size corrupted file, an HTML "preview.png" →
  `not an image (text/html), deleted`, a right-size wrong-hash PNG → `sha256 does not match`, a 9 MiB
  file → `larger than 8388608 bytes, deleted`; `theme set` → detached fetch → link appears; bg list
  order, `next` cycling `2-b.jpg 3-c.webp 0-mine.png 1-a.png`, restart only when the unit is active,
  dry-run tree purity, refusals; `bg run --dry-run`; layer apply dry run; the font override.
- `/tmp/tools/shellcheck --severity=warning -x` + `bash -n` on the 3 new commands, theme-set,
  layer.sh, theme-lib.sh and both tests: clean. `jq empty` on the manifest and 16 `vscode.json`;
  `luac -p` on every theme Lua. qmllint (tools/lint.sh flags): 0 errors. `tools/check-docs.sh` OK.
  `haseen plugin validate haseen.themepicker` → ok.
- Real fetch, scratch `XDG_CACHE_HOME=/tmp/themes-real/cache`, `haseen theme fetch tokyo-night` (10 s):
  `0-winding-road.webp 653482`, `1-quattro.webp 625422`, `2-swirl-buck.webp 344156`,
  `3-sunset-lake.webp 364966`, `4-omakub.webp 184050`, `5-oma-cityscape.jpg 1408419`, `6-oma.webp 280578`,
  `omarchy.webp 716`, `preview.png 382202`; `file --mime-type` webp/jpeg/png; second run
  `(0 fetched, 9 cached)`. A real resume happened: kanagawa's `1-kanagawa.jpg` failed with curl 56
  (connection reset) at 229 358 bytes; the rerun resumed it, 1 624 027 bytes, hash verified.
- Live (scratch `XDG_CONFIG_HOME`/`XDG_STATE_HOME`/`XDG_CACHE_HOME`/`XDG_RUNTIME_DIR`, services `[]`,
  idle/lock disabled, `HASEEN_THEME_HEADLESS=1`, final runs under
  `dbus-run-session --config-file=tools/smoke-session.conf`), IPC only: `panel toggle haseen.themepicker`
  → `state` `count 22`, 4 `:preview` (fetched) and 18 `:palette`; `select catppuccin`, `move right`,
  `move down` → `gruvbox`; `accept` → scratch `theme.name` = gruvbox, panel closed, reopened with the
  shell re-themed (gruvbox surface/accent) and gruvbox marked active. Screenshots viewed:
  `/tmp/themes-smoke/picker-crop.png`, `picker-gruvbox.png`, `picker-final.png`. The owner's
  `~/.local/state/haseen` and `~/.cache/haseen` do not exist before or after.
- Idle RSS (scratch instance, 30 s idle, then open 3 s, close, 25–30 s idle; CPU 0 s throughout):

| picker content | idle before | after first open+close | delta |
|---|---|---|---|
| never opened | 110 360–111 112 kB | — | 0 (lazy) |
| palettes only (empty cache) | 110 596 kB | 113 832 kB | +3.2 MiB |
| 4 full 1800x1012 previews | 110 360 kB | 159 976 kB | +48.5 MiB |
| 4 `preview-thumb.png` | 110 568 kB | 139 112 kB | +27.9 MiB |
| 1 `preview-thumb.png` | 111 112 kB | 138 324 kB | +26.6 MiB |

  Reopening three more times did not grow it (166 244 → 166 432 kB). Synchronous decoding and a fixed
  `MALLOC_MMAP_THRESHOLD_` changed nothing material, so the ~25 MiB is the one-off cost of the first
  image in the process, not per image; thumbnails remove the per-image part. **Over the §6 10 MiB
  note threshold after the picker has been opened once with previews; zero until then.**

### Rejected

- **Shipping images** (plan 004's reasons stand: third-party artwork, 64 MB).
- **Branch URLs / the GitHub contents API**: branch raw URLs are cached and stale (omacachy); the API
  is rate-limited and needs JSON parsing. The manifest pins names, sizes and hashes instead.
- **Copying `chromium.theme` and `shell.lock.toml`**: nothing in haseen reads them.
- **Per-card fallbacks in QML** (try user path, on error the next): every miss logged a warning, and
  changing a `FileView` path mid-load dropped the read ("got operation finished from dropped
  operation"), leaving cards blank. One `find` up front gives each card its final paths.
- **`gdk-pixbuf-thumbnailer`**: not shipped by Arch's gdk-pixbuf2 2.44 (`pacman -Ql`);
  `glycin-thumbnailer` is.

### Not verified

- swaybg itself (not installed here; no installs): `haseen-background.service` and `bg run` were only
  exercised as dry runs. WebP via swaybg relies on gdk-pixbuf2 2.44 loading through glycin
  [INFERENCE]; glycin decoded the tokyo-night WebP here (`glycin-thumbnailer` → 256x144 PNG).
- The NixOS side (home-manager unit, `pkgs.swaybg`). Moot since 2026-10-05: Nix support was dropped (plan 009).
- The first two scratch launches ran under a plain `dbus-run-session` (before the
  `tools/smoke-session.conf` rule); xdg-desktop-portal-hyprland crash notifications were on screen
  around then and may have come from them.
