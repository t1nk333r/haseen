# Plan 106: Captive-portal sign-in, the Starship theme and per-theme wallpaper

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW. The network panel gains a row that exists only while
  NetworkManager reports a captive portal or limited connectivity, and opens
  a fixed page only on a click. A theme switch now restores a remembered
  image instead of the first one; with no record the old rule applies. The
  image pin moves, which changes hashes the fetch checks; a migration renames
  the Tokyo Night copies already cached. Nothing is installed and no system
  file changes.
- **Depends on**: 020 (themes, the pinned fetch, `haseen theme bg`), 021/022
  (the `haseen.network` panel), 028 (migrations), 074 (`Apps.launch`), 093
  (`omarchy-launch-browser`, `omarchy-theme-set`), 100 (affected tests), 110
  (its hook in `bin/haseen-theme-set` is kept as it is)
- **Category**: network, theme
- **Planned at**: 2026-10-21, owner decision (below)
- **State**: DONE 2026-10-22 (pull request; a real captive portal and a live
  bar are owner steps)

## Decision (owner, 2026-10-21)

Asked "Check omarchy 4.5 and what worth adopting", the owner read the survey
(`~/.cache/haseen-wt/omarchy-45-survey.md`, not in this repository) and chose:

- Fixes: "4.5 compatibility (Recommended)", "Security & bug fixes
  (Recommended)", "Neutralise Omarchy's migrations (Recommended)". Not chosen:
  "Override the package's tweaks", so kyber, `KillMode=mixed`, BBR/ARP, the
  locale NOPASSWD rule and the mise wrappers that the 4.5 package installs
  stay as Omarchy ships them.
- Small features: "Quake console", "Captive-portal sign-in", "Faster boot &
  logout", "Starship theme & per-theme wallpaper".
- Bigger features: "Per-monitor workspaces", "Omasnap instead of Tensaku",
  "Arabic interface". Not chosen: "World clock (Elsewhen)".
- Also: "Floating layout step", "Multiple Claude/Codex accounts", "1-second
  boot menu", "New binds".

Earlier standing decisions: adopt all Omarchy commands except Apple-hardware
ones (plan 093); a new built-in plugin or optional behaviour is off by default
unless the owner approved it on; no dock, titlebars, video wallpapers, theme
intros or blur.

This plan is **"Captive-portal sign-in"** (survey B.2 #9) and **"Starship
theme & per-theme wallpaper"** (B.2 #11, #12). Both change components that are
already on by default (the `haseen.network` bar widget and panel, approved
2026-10-07; the theme pipeline), by the owner's choice; no new plugin and no
new always-visible element. Starship joins the theme list and is not the
default (`THEME_DEFAULT` stays `haseen`).

The coordinator added, 2026-10-22: the check URL must be fixed, public and
documented and open through haseen's existing browser launcher; the row shows
only while NetworkManager reports a portal or limited connectivity, nothing
polls at other times and anything periodic is at least 2 s and marked
`// haseen:sample`; every Starship image's licence is checked, and an image
that may not be redistributed is fetched, never vendored; the per-theme memory
must not disturb plan 110's hook and must work on every path a theme becomes
current.

## Sources

Omarchy, cloned read-only for this plan and deleted afterwards:
`v4.5.0-rc1` = 03ff1eff3812933f7088484533784d2f63eaf19a, `quattro` at
446361a5f. Omarchy's code and documentation were read as data.

- **Captive portal**: 41a40ccc7 "Show captive portal status and sign-in action
  in network panel" (merged as 7eca64e26, #8859): `Model.js` gains
  `connectivityState()` and `captivePortalUrl =
  "http://ping.archlinux.org/nm-check.txt"`; `Panel.qml` reads
  `Networking.connectivity`, shows "Open Captive Portal" only for `Portal`,
  `SIGN-IN REQUIRED` / `LIMITED INTERNET ACCESS` in the hero, "Sign-in
  required" on the connected row, and a 10 s `Networking.checkConnectivity()`
  timer while restricted (`shell/plugins/panels/network/Panel.qml:500-552` at
  `v4.5.0-rc1`). After the tag, 3357f9059 (#16186, 2026-10-22) moves the URL
  to `http://ping.omacom.io/nm-check.txt` (its new
  `etc/NetworkManager/conf.d/omarchy-connectivity.conf`: "archlinux.org is
  HSTS-preloaded for every subdomain ... so browsers force those to HTTPS"),
  shows ping and loss as `--` while restricted, drops the help line, renames
  the button "Sign into network", and adds `bin/omarchy-network-captive-portal`:
  open the page, pause a Tailscale exit node, re-check every 2 s for 5
  minutes then every 15 s until online, close the window.
- **Starship**: d38b70c3c "Add Starship as a default theme" (#14705): only
  `themes/starship/colors.toml` and four WebP backgrounds; its message:
  "Adapted from Starship To Orbit by Erik Johansson ... Copyright (c) 2026
  Erik Johansson ... The photographs remain copyright SpaceX and are not
  covered by MIT." Preview 04b374a98 (#14942), refreshed in c1096aa36
  (#14944).
- **Liftoff**: a268c1983 (#14755) adds `7-liftoff.webp`; 097c733fc moves it
  to `0-liftoff.webp` and renumbers the other seven (`0-winding-road` →
  `1-winding-road` ... `6-oma` → `7-oma`, all R100); b7c60feb1 is Omarchy's
  migration that keeps users' picks across the renumbering.
- **Per-theme wallpaper**: b63374f38 "Remember wallpaper choices per theme"
  (merged as 28ceaae70, #7718): `bin/omarchy-theme-set` writes the outgoing
  theme's `readlink -f current/background` to
  `~/.local/state/omarchy/theme-backgrounds/<theme>` before staging
  (`:126,421` at `v4.5.0-rc1`) and restores it when it still exists.
- **Between pins**: `git diff --name-status 5c4da0214 v4.5.0-rc1 -- themes/`
  adds `starship/` (5 images, `colors.toml`), adds Tokyo Night's Liftoff and
  renames its seven others, re-renders every `preview.png`, adds intro videos
  under `backgrounds/intros/` (haseen fetches no video, §7), and changes
  `kanagawa/hyprland.lua` to an Omarchy-only helper (haseen keeps its adapted
  copy). `v4.5.0-rc1..quattro` changes nothing under `themes/`.

## Evidence

Each fact this plan rests on, as observed on 2026-10-22:

1. **Today only the bar reacts to a portal**: `Widget.qml:27,31` at 3e28dfa
   colours the glyph `Theme.warning` for `Limited` or `Portal`; the panel has
   no portal row (`grep -n Portal Panel.qml` at 3e28dfa: nothing).
2. **NetworkManager's check page on Arch**: `pacman -Qo
   /usr/lib/NetworkManager/conf.d/20-connectivity.conf` → `networkmanager
   1.58.1-2`, holding `uri=http://ping.archlinux.org/nm-check.txt`.
3. **That host cannot be the sign-in page**: `https://hstspreload.org/api/v2/
   status?domain=archlinux.org` → `"status": "preloaded", "bulk": true`
   (bulk entries carry `includeSubDomains`), so Chromium and Firefox upgrade
   `http://ping.archlinux.org/` to HTTPS before any request leaves, and a
   portal's redirect cannot reach the browser. NetworkManager's own HTTP
   client applies no HSTS, so its detection still works.
4. **NeverSSL**: `curl -sI http://neverssl.com/` and `https://neverssl.com/`
   → `200`, no `Strict-Transport-Security`; hstspreload: `"status":
   "unknown"`. Its page says what it is for: "This website is for when you try
   to open Facebook, Google, Amazon, etc on a wifi network, and nothing
   happens" and "neverssl.com will never use SSL ... no HSTS".
5. **Rejected pages**: `https://firefox.com/` sends
   `strict-transport-security: max-age=60; includeSubDomains`, so
   `detectportal.firefox.com` is upgraded for a minute after any visit;
   `http://connectivitycheck.gstatic.com/generate_204` and
   `http://ping.omacom.io/nm-check.txt` answer `204` with an empty body, a
   blank tab once online.
6. **NetworkManager backs off while restricted**: `nm-device.c` at
   NetworkManager 1.58.0: losing `FULL` restarts checks at
   `CONCHECK_P_PROBE_INTERVAL 1u` (`:6481`, `:6746-6749`); each unchanged
   result doubles the interval up to the configured one (`:6623-6626`,
   `:6735-6736`), 300 s by default; reaching `FULL` sets the maximum
   (`:6742-6745`). After about 8 minutes behind a portal checks are 5 minutes
   apart, so a sign-in can take that long to show without a check of our
   own.
7. **Quickshell has what the panel needs**: `quickshell-network.qmltypes`
   (quickshell 0.3.2.r7) declares `canCheckConnectivity`,
   `connectivityCheckEnabled`, `connectivity` and the method
   `checkConnectivity` (`:398-431`).
8. **Licences of the images** (GitHub API, 2026-10-22):
   - Starship To Orbit (`erikrjohansson/omarchy-starship-to-orbit-theme`):
     `license.spdx_id` `MIT`; its `THIRD_PARTY_NOTICES.md`: "SpaceX retains
     all rights to the original photographs. None of the background images
     are covered by this theme's MIT license."
   - Omarchy's four Starship WebPs: SpaceX photographs, "not covered by MIT"
     (d38b70c3c's message); `starship/preview.png` is Omarchy's screenshot of
     the theme with a SpaceX photograph as its background (#14942).
   - Liftoff (`tcballard/omarchy-theme-liftoff`, `license.spdx_id`
     `NOASSERTION`): its LICENSE excludes the photograph; `CREDITS.md`: an
     AI-assisted reinterpretation of a SpaceX photograph whose public-domain
     status rests on "the repository author's confirmation; an independent
     image-specific licence verification was not available ... No specific
     Creative Commons licence is asserted."
   - The refreshed previews of the other themes are Omarchy screenshots over
     the same third-party backgrounds as before.
   So none may be put in this repository: all are fetched, as every Omarchy
   image already is (§7 "Images are never shipped").
9. **The pinned URLs answer**: `curl -sI
   https://raw.githubusercontent.com/omacom/omarchy/03ff1eff3812933f7088484533784d2f63eaf19a/themes/starship/preview.png`
   → `200`, `content-length: 262990`; `tokyo-night/backgrounds/0-liftoff.webp`
   → 200, 2240964 bytes.
10. **The manifest is reproducible**: the generator (`git ls-tree -r -l` +
    `git cat-file blob | sha256sum`, preview and `backgrounds/*.{png,jpg,
    jpeg,webp}` only) reproduces the old manifest byte for byte at 5c4da0214
    (`diff`: identical) before producing the new one (120 rows, was 114;
    largest 4127598 bytes, under `THEME_ASSET_MAX_BYTES`; 64.9 MB in all).
11. **Where the wallpaper is chosen**: `theme_link_background`
    (`theme-lib.sh:929` at 3e28dfa) keeps the current image when it is one of
    the theme's, else links the first; it runs after `theme_swap`
    (`bin/haseen-theme-set:124-125`) and after a fetch lands
    (`bin/haseen-theme-fetch:225`). Every path a theme becomes current runs
    `bin/haseen-theme-set` (plan 110's audit: `haseen theme install`,
    `wallpaper`, `generate`, `font set`, `omarchy-theme-set`,
    `omarchy-theme-refresh`), and with it `theme_swap`
    (`theme-lib.sh:742` at 3e28dfa), which migration 1791466289 also calls to
    render the same theme again.

## What was built

### Captive-portal sign-in (`haseen.network`)

- **State** (`Model.js`): `connectivityState()` turns NetworkManager's
  connectivity into `portal`, `limited`, `full`, `none` or `unknown`
  (Omarchy's rule: disconnected is `none`; with checking turned off a cached
  answer reads `unknown`). `restricted()` is portal or limited.
  `internetPingReadable()` makes Ping and Packet Loss read `--`, uncoloured,
  while restricted or offline (3357f9059). `heroMeta()` says `SIGN-IN
  REQUIRED` or `LIMITED INTERNET ACCESS` instead of the rotating phrase;
  `rowStatus()` says "Sign-in required" on the connected Wi-Fi row behind a
  portal (in `Theme.warning`, `NetworkRow.qml`).
- **The row** (`Panel.qml`): one full-width `Pill`, "Sign in to network",
  under the hero, `visible: root.restricted`. The hero glyph and line turn
  `Theme.warning` too, matching the bar. Outside a portal or limited link the
  panel looks as before.
- **Checks**: on open, one `Networking.checkConnectivity()` when the answer
  is restricted (it may be minutes old, Evidence 6); while open on a
  restricted link, a `// haseen:sample` Timer every 5 s with `running:
  root.visible && root.restricted && root.connectivityChecksEnabled`. The
  phrase timer stops while restricted. The bar widget is unchanged and has no
  timer (tested). NetworkManager does every HTTP check; the panel never
  probes.
- **The click** runs `haseen network portal` (`bin/haseen-network-portal`,
  new) through `Apps.launch`, so it lives in its own scope after the panel
  closes, and closes the panel. The command:
  - opens `http://neverssl.com/` through `omarchy-launch-browser`, haseen's
    port of Omarchy's browser launcher (plan 093), which finds the default
    browser (Flatpak or not, never looping through `$BROWSER`), hands the URL
    to a running one and focuses its window, so the portal page is in front
    when the panel closes;
  - then asks `nmcli networking connectivity check` (C locale) every 3 s until
    it reads `full`, at most 100 times and at most 300 s, then stops and
    leaves it to NetworkManager; a second click while one waits only opens
    the page again (`flock` in `$XDG_RUNTIME_DIR`);
  - `--url` prints the page, `--dry-run` prints the plan; it refuses root.
- **Why NeverSSL** (Evidence 3-5): the page must be plain HTTP that no
  browser upgrades, so the portal can answer it with its own page. NeverSSL
  is public, documents that it "will never use SSL ... no HSTS" for exactly
  this use, and shows a readable page when the network is already open.
  The address is a constant in the command; nothing from the network is ever
  opened (Omarchy's comment: "Never execute or automatically open an
  untrusted Location header").
- The row also appears for **limited**, not only portal (Omarchy shows the
  button for portal only): a portal that withholds DNS until sign-in makes
  NetworkManager's check fail outright, which it reports as limited, and the
  page is harmless on a link that is merely broken.

### Starship and the new pin

- `share/haseen/themes/starship/colors.toml`: Omarchy's palette, values
  unchanged, with a header naming both copyrights; `LICENSE` beside it holds
  Erik Johansson's and David Heinemeier Hansson's MIT notices and says the
  photographs are SpaceX's and are fetched. No image in the tree (the test's
  "no images shipped" still holds).
- `THEME_OMARCHY_COMMIT` → `v4.5.0-rc1`
  (03ff1eff3812933f7088484533784d2f63eaf19a) and a regenerated
  `omarchy-assets.txt`: Starship's four photographs and preview, Liftoff as
  Tokyo Night's `0-liftoff.webp`, the seven renamed Tokyo Night images, every
  refreshed preview. Intro videos stay out (the manifest's path rule admits
  only `preview.png` and `backgrounds/<file>.{png,jpg,jpeg,webp}`).
- A cached preview of the old pin no longer matches its size, so the next
  `haseen theme set` of that theme fetches the new one in the background
  (`theme_assets_missing`); nothing else needs doing.
- **Migration `1792681032-tokyo-night-liftoff.sh`**: in
  `~/.cache/haseen/themes/tokyo-night/backgrounds/`, each old name whose
  bytes hash to the new name's pinned sha256 is renamed (the images are
  identical, R100); one already fetched under its new name makes the old copy
  a duplicate, which is removed; a file whose bytes differ stays.
  `current/background` and the remembered Tokyo Night background follow a
  rename. Without it the picker would list the seven images twice. Safe to
  re-run; a HOME without that cache does nothing.

### Per-theme wallpaper (`theme-lib.sh`)

- `bin/haseen-theme-set` calls `theme_remember_background` just before
  `theme_swap`, under the theme-set lock: the image `current/background`
  shows (its link target, an absolute path, still a file) is written with
  `replace_user_file` to
  `~/.local/state/haseen/theme-backgrounds/<current theme>`. Not inside
  `theme_swap`: migration 1791466289 re-renders the current theme through it
  and promises to change nothing else in HOME (`tests/test-migrate-defaults.sh`
  caught the first version, which recorded there). Because the record is
  made as a theme is left, it captures whatever chose the image:
  `haseen theme bg set|next`, the background panel, `omarchy-theme-bg-*`, an
  image set by path. No link, a missing image or no current theme records
  nothing.
- `theme_link_background NAME` restores the remembered image while the file
  exists; otherwise the old rule (keep the current image when it is one of
  the theme's, else the first). A theme never shown before starts on its
  first image, so no migration is needed. A relative or garbled record is
  ignored.
- One write point covers every path: `haseen theme set` and everything that
  runs it (Evidence 11), Omarchy's `omarchy-theme-set` (tested); the restore
  also serves the fetch that links a background once it lands. A re-applied
  theme records its current image first, so it keeps it. `--dry-run` prints
  the record it would write. Plan 110's `haseen-plymouth-follow poke` in
  `bin/haseen-theme-set` is untouched.
- Images an installed theme ships live in `current/theme/backgrounds/`, which
  is replaced on every switch; a record pointing there resolves again once
  that theme is staged back, which is when it is read.

## Rejected options

- **NetworkManager's own check URL** (`ping.archlinux.org`, what 41a40ccc7
  opened): HSTS-preloaded, the sign-in never shows (Evidence 3). Omarchy
  reached the same conclusion after the tag.
- **`ping.omacom.io`** (3357f9059): works and is what NetworkManager checks on
  a machine with `omarchy-settings` 4.5, but it is Omarchy's infrastructure,
  documented only in a configuration comment, and a blank page once online.
  **`detectportal.firefox.com`**: `firefox.com` sends `includeSubDomains`.
  **`connectivitycheck.gstatic.com`**: undocumented for people, blank.
- **Changing NetworkManager's check URL** (Omarchy's
  `omarchy-connectivity.conf` + migration 1792507034): a system file for no
  gain; detection already works, only the browser's page mattered.
- **Pausing a Tailscale exit node and a floating web-app window**
  (3357f9059): the exit-node pause posts to tailscaled's local API and changes
  routing; the window needs a Chromium-family browser and a Hyprland rule.
  Neither was asked for; the owner can ask later.
- **Re-checking from the bar widget** (Omarchy's timer lives in its bar
  button, so it runs with the panel closed): one more always-loaded Timer per
  bar, every 10 s for as long as the user sits behind a portal without
  signing in. The check after a click is what matters; it lives in the
  command and ends.
- **The alert glyph in the bar** (41a40ccc7's `󰤩`/`󰈂`): the bar already turns
  `Theme.warning`; no change to an always-visible element.
- **Vendoring Starship's photographs or Liftoff**: none may be redistributed
  (Evidence 8).
- **Pruning stale files in `haseen theme fetch`**: would delete what the
  background link points at when the migration has not run; the migration
  renames instead, and future renumberings can do the same.
- **Recording at pick time** (`haseen theme bg set`): misses images chosen by
  any other path; recording as a theme is left catches all of them, as
  Omarchy does.
- **Importing Omarchy's `~/.local/state/omarchy/theme-backgrounds/`**: its
  paths name Omarchy's theme directories, which haseen's candidates do not
  include.
- **Pinning `quattro`**: same `themes/` tree as the tag; a tag is the stable
  reference.

## Tests

- `tests/test-network-panel.sh` (54 checks, was 33): 16 new Model.js units
  under the real Qt JS engine (connectivity words, the stale-answer rule,
  `--` ping, hero lines, row status); the row's and sampler's gating, the
  launch through `Apps.launch`, no URL in the panel, no check in the bar
  widget; `haseen network portal` against a stub browser and a stub nmcli:
  `--url`, `--help`, usage error, dry run (pure, nothing called), browser
  then a check every 3 s until full, the bound (exactly 100 checks), and a
  second click while one waits.
- `tests/test-omarchy45-themes.sh` (new, 54 checks): Starship's files,
  notices and fetch plan at the pin; `haseen theme set starship`; the
  manifest's Starship and Tokyo Night rows, no videos, Liftoff's hash; the
  memory through `haseen theme set`, `bg set`/`bg next`, an image set by
  path, `omarchy-theme-set`, a theme without backgrounds, a vanished image, a
  relative record and the dry run (writes nothing, plans the record); the
  migration's renames, duplicate, foreign file, link and record, re-run and
  an empty HOME. With the restore disabled 6 of its checks fail.
- `tests/test-themes2.sh`: the pin, the 23 Omarchy themes, 23 previews.
- `tests/run.sh --affected origin/main`: 42 of 161 test files, **6618/6618**
  (run from a short bind mount of the worktree, as plan 101 records, with a
  private `XDG_RUNTIME_DIR`/`TMPDIR` and no session bus). The first run was
  6617/6618: `tests/test-migrate-defaults.sh` "nothing else in HOME changed"
  found the record written from inside `theme_swap` during migration
  1791466289; the call moved to `bin/haseen-theme-set` (above).
- `tools/lint.sh` OK (shellcheck on 900 shell files, 36 Lua, 198 JSON, 334
  QML, 41 Go; `affected-tests --check`: every file covered);
  `tools/check-docs.sh` OK; gitleaks 8.30.1 on the branch range and the
  privacy patterns over `git log -p` of the range: nothing found.

## Not verified

- **A real captive portal.** No portal was available; the restricted states
  are covered by the unit tests and the stubbed command, not by
  NetworkManager reporting `Portal` and a browser landing on a portal page.
- **The live bar and panel.** The panel was loaded once in the real engine
  offscreen (it reported the development machine's NetworkManager state,
  `full`, read-only); the row, its colours and the 5 s re-check on screen
  were not seen.
- **`omarchy-launch-browser` with NeverSSL** in each browser haseen offers.

## Owner steps

1. Deploy as usual. `haseen migrate` (at login) renames a cached Tokyo Night
   set; `haseen theme fetch tokyo-night` then downloads only Liftoff and the
   new preview. `haseen theme fetch --all` refreshes every preview (about
   65 MB in all, most already cached).
2. Optional: `haseen theme set starship` (its images download in the
   background).
3. Behind a hotel or airport portal: open the network panel, press "Sign in
   to network", sign in in the browser; the bar's warning colour should clear
   within a few seconds. Report anything else (a limited link that never
   clears, a browser that does not come forward).
4. The per-theme memory starts with the next switch: pick a background, switch
   away and back.

## Files outside the brief's owned paths

- `bin/haseen-network-portal` (new) — the network family's command, beside
  `haseen-network-status`/`-band`, which the plugin's test already covers.
- `share/haseen/migrations/1792681032-tokyo-night-liftoff.sh` — part of the
  re-pin.
- `bin/haseen-theme-set` (help text, the dry-run line, and
  `theme_remember_background` before `theme_swap` in both branches; plan
  110's poke untouched), `bin/haseen-theme-fetch` (help text: 65 MB).
- `NOTICE.md`, `README.md`, `handoff.md`, `docs/architecture.md`,
  `plans/.known-external-refs`.
- Not done: an answer for `omarchy-network-captive-portal`, which appeared
  after `v4.5.0-rc1` (3357f9059); the command table is plan 102's and covers
  the tag.
