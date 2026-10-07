# Plan 064: plugin requirement gates and the palette anchor clamp

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW (a plugin is refused only for a requirement it declares; colours of wallpaper themes move only where contrast was too low)
- **Depends on**: 005 011 034
- **Category**: shell, plugins, theme
- **Planned at**: 2026-10-07, owner request: two ideas from aphotic-hypr (GPL-3.0, ideas only; no code or text taken)
- **State**: DONE 2026-10-07 (`tests/test-plugin-gates.sh` 48/48 with the shell part in Quickshell; `go test ./...` in `core/`; nested-session screenshot of the refusal notification; the live io session is an owner check)

## Problem

1. A plugin that needs a command, a haseen layer or a newer haseen loaded
   anyway and failed at runtime, often silently (a `Process` whose binary is
   missing just exits). DMS plugins declare `dependencies` in `plugin.json`
   (DankMaterialShell `quickshell/PLUGINS/plugin-schema.json`: "Array of
   required system tools/dependencies (registry metadata)", plus the
   deprecated alias `requires`), but DMS itself never enforces them.
2. Themes generated from a wallpaper (`haseen-palette`, `core/internal/palette`)
   had no floor on contrast. A scan of 132 synthetic images × 23 modes × light
   and dark found the light-mode selection under the foreground down to 3.52:1
   (image "grey-wash": `#696080` on `#c8cbb1`), below the 4.5:1 theme-lib
   already demands for `shell_selection`
   (`share/haseen/layers/theme/theme-lib.sh` `_theme_shell_selection`).

## Decision

### Plugin gates

- **Manifest field** `requires` (`share/haseen/shell/plugin.schema.json`):
  `bins` (commands on PATH, strict), `tools` (command or package names, the
  DMS kind of list), `layers` (applied haseen layers, the state file
  `/var/lib/haseen/layers/<name>` that `layers.sh` `layer_is_applied` reads)
  and `haseen` (minimum version, major.minor.patch only so `0.1.0-dev`
  satisfies `0.1.0`).
- **One rule set, two implementations, one wording.**
  `share/haseen/shell/Haseen/Requires.js` (shape check, fact keys, messages)
  and `share/haseen/shell/lib/plugin.sh` (`plugin_check` jq rules,
  `plugin_unmet`, `plugin_requires`). The test compares the shell's
  messages with the CLI's for the same plugins.
- **The shell** (`Haseen/Plugins.qml`): a plugin is `valid` only when its
  manifest is valid and every requirement is met. Facts are probed in one
  `bash` run (`Process` `requirementProbe`) for all keys not known yet; no
  polling. `ready` waits for that probe, so no host loads a plugin before it
  is decided; a plugin whose facts are still unknown is `checking` and
  silent. Unmet reasons go into `errors` (and `shell plugins` over IPC as
  `unmet`), are logged once, and the first time a host asks for the plugin
  (`noteMissing`) one `notify-send` names the reasons. Facts are dropped and
  probed again when the set of plugin directories changes and on reload.
- **The CLI**: `haseen plugin validate` prints `unmet: <id>` with one
  `requires: …` line per reason and exits 1; `list` shows state `unmet` with
  the reasons after the name; `info` adds `needs:` and the unmet state;
  `enable` still enables but warns that the shell will not load it.
- **Compat**: DMS `dependencies` and its alias `requires` become
  `requires.tools` (`Compat/Manifest.js` `toolsFrom`, jq `toolsfrom`), dropping
  entries that are not plain names. Omarchy's manifest has no requirement
  field (its `shell/services/PluginRegistry.qml` requires only `id`, `name`,
  `version`, `kinds`, `entryPoints`; none of the 37 manifests in the owner's
  set declares one, only `minHelperVersion`, a plugin-specific helper), so an
  Omarchy manifest may carry haseen's `requires` object as is (Omarchy
  ignores unknown keys); an array there is read as `tools`.
- **`tools` is lenient on purpose.** On io the owner's enabled
  `dms.screen-capture-toolbar` lists `wl-clipboard` (an Arch package, not a
  command) and `pulseaudio-utils` (Debian's name; `pactl` comes from
  `libpulse` on Arch). A tool is met by a command on PATH, an installed
  package or provider (`pacman -T`), and a name no repository knows
  (`pacman -Si` fails) counts as met because it cannot be checked. Checked on
  io (read-only, worktree CLI against the live config): the toolbar stays
  `ok`; `dms.tlp-power-profile` (`tlp`) is unmet; neither of those is
  refused wrongly.
- **The shell's PATH counts.** `bin/haseen-shell-run` puts
  `shell/Compat/bin` first, so a shimmed command (`ydotool`, `dms`) is met;
  `plugin_unmet` looks commands up with the same PATH
  (`dms.virtual-keyboard` needs `ydotool` and is `ok` for that reason).

### Palette anchor clamp

- `core/internal/palette/anchors.go` `ClampAnchors(palette, light)` runs as the
  last step of `Generate` (`generate.go`, both the cache-hit and fresh paths),
  so every wallpaper-derived theme in all 23 modes, light and dark, passes:
  - foreground (`color7`, also the cursor) ≥ 4.5:1 on the background (`color0`);
  - accent (`color4`) ≥ 3:1 on the background (WCAG 1.4.11);
  - selection (`selection_background`, now `Result.Selection`) under the
    foreground ≥ 4.5:1, what `_theme_shell_selection` checks, so
    `shell_selection` equals `selection` for generated themes.
- Contrast is the existing `ContrastRatio` in `accessibility.go`, the same
  formula as `_theme_contrast`. The background never moves. Each anchor keeps
  its OKLCH hue and chroma and only its OKLab lightness moves: 24 bisections
  toward the far end (white or black) find the smallest change that passes;
  chroma is lowered only when the colour leaves sRGB. Passing colours are
  returned unchanged; the bright twins (`color15`, `color12`) are rebuilt when
  their anchor moved.
- `oklab.go` had a wrong third row in the linear-sRGB→LMS matrix
  (0.2164557844/0.6952417517 instead of Ottosson's 0.2817188376/0.6299787005),
  so round trips drifted (`#0000ff` → `#2100ff`). Fixed, with a round-trip
  test; `cacheVersion` 1 → 2 because generated palettes change slightly.

## Rejected

- **Gating DMS `dependencies` as strict commands** (the first version): it
  refused the owner's working screen-capture toolbar for `pulseaudio-utils`.
- **A `pacman -Q` fallback for `bins`**: a native plugin that says "command"
  should mean a command; the leniency is confined to `tools`.
- **Mapping DMS `requires_dms`**: a DMS version says nothing about haseen.
- **Flipping `ready` false only for new facts after start / a latch**: `ready`
  already goes false while new manifests load, so the probe follows the
  same rule instead of a second readiness notion.
- **Re-probing on a timer**: no polling (architecture §6); reload or a plugin
  directory change probes again.
- **Clamping before the palette cache**: older cache entries would come out
  unclamped. **Searching both directions for the smallest ΔL**: could flip a
  dark theme's text to dark. **Mixing in RGB like theme-lib**: shifts hue.
- **A `haseen-palette --clamp FILE` entry point** for plan 067: rewriting an
  arbitrary `colors.toml` with its aliases is more than this plan; 067 was
  told to use theme-lib's helpers or `palette.ClampAnchors`.

## Evidence

- `tests/test-plugin-gates.sh`: CLI validate/list/info/enable, strict `bins`
  against installed packages, layers through `HASEEN_SYSROOT`, the version
  floor, malformed `requires`, DMS and Omarchy mappings; then the real
  `Haseen/Plugins.qml` in Quickshell (offscreen) refusing the same plugins
  with the CLI's messages, other plugins loading, and exactly one
  notification for a refused plugin asked for twice. 48/48.
- `tests/test-compat.sh`, `test-shell.sh`, `test-compat-desktop.sh`,
  `test-compat-runtime.sh`, `test-dms.sh`, `test-core.sh`, `test-theme.sh`,
  `test-themes2.sh`, `test-wallpaper.sh` and `test-sidecar.sh` (with `GO`):
  unchanged and passing.
- Nested Hyprland (`nest-launch.sh`, scratch HOME, private D-Bus): the
  worktree shell with an enabled user plugin needing `haseen-demo-tool` and
  layer `gaming` logged both reasons, left the plugin unloaded, and haseen's
  own notification card read "Gated Demo not loaded" with both reasons and
  the reload hint (`grim -o IO`, kept at
  `~/.cache/haseen-wt/PluginGates/plan064-refused-toast.png`; the second card
  in that shot is the previous run's, kept by the pager's history). The
  notification is critical so it stays until read, as `DmsStartupGate`'s.
- `core/internal/palette/anchors_test.go`: five low-contrast images × 23
  modes × light/dark through `Generate` meet the three floors with the
  background fixed and OKLab hue shift ≤ 0.01; hand-made sets (mid-grey
  background `#6e6e6e`: foreground 1.81 → 4.51, accent 1.51 → 3.02; light
  pastel `#e9dff0`: foreground 1.44 → 4.53, accent 1.35 → 3.00) check
  direction, minimality and idempotence; passing palettes come back
  unchanged.

## Live apply (io)

`haseen shell restart` (or `haseen shell ipc shell reload`) after the update.
Regenerating a wallpaper theme (`haseen theme wallpaper`) re-runs the
generator once because of the cache bump.

## Not verified

- The notification on the owner's live io session, and the first run of a
  regenerated wallpaper theme on screen.
- `pacman -Si` on a machine without synced databases treats every unknown
  tool as met (the lenient side).
