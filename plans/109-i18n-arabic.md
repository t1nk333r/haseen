# Plan 109: haseen in Arabic and English

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MEDIUM. Every panel's strings and the layout of every native
  panel change for Arabic; for English nothing should look different. A
  string that leaks the catalog shows in English, never as a raw key. The
  Arabic is a machine translation and says so (`ar/provenance.json`).
- **Depends on**: 005 and 011 (shell and compat host), 016/068 (the menu),
  047 (Arabic fonts and shaping), 100 (affected tests), 105, 106 and 108
  (whose new strings this routes)
- **Category**: shell, Omarchy compatibility
- **Planned at**: 2026-10-21, owner decision (below)
- **State**: DONE 2026-10-22 in a pull request (counts below), with review
  r1's fixes (jq option values, the menu's brand mark, English parity of
  dates and snooze lengths, the language file's first line, the catalog
  check in lint) and review r2's (a BOM or CRLF language file read alike
  in bash and the shell); a live Arabic session and the owner's review of the
  Arabic are owner steps

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
  "**Arabic interface**". Not chosen: "World clock (Elsewhen)".
- Also: "Floating layout step", "Multiple Claude/Codex accounts",
  "1-second boot menu", "New binds".

This plan implements "Arabic interface": haseen's menus, panels and
notifications in Arabic and English. English stays the default; Arabic is
the owner's explicit `haseen language ar`. Standing decisions kept: adopt
Omarchy's commands but the Apple ones (plan 093); nothing new on screen
without a reason; no polling under 2 s; panels load lazily.

## Problem

haseen had no interface language: QML strings were literals, the menu's
labels English in `share/haseen/default/menu.jsonc`, and the only
translation surface the DMS compat stub
(`share/haseen/shell/Compat/Dms/Common/I18n.qml`), which returns every string
as written. Arabic existed only as content (prayer names, day names), fonts
(plan 047), the fcitx5 switch and OCR.

Omarchy 4.5 added 50 languages (verified against a read-only clone of
`basecamp/omarchy`, tag `v4.5.0-rc1`):

- 84cfb9395 (#15326, "Omarchy in 50 languages") and follow-ups such as
  dd07b6269 (#15791, "Push a new language's LANG into Hyprland and the
  shell"): flat JSON catalogs `default/i18n/<code>/{shell,menu,cli,keybindings}.json`
  keyed by dotted ids (`"agents.addAccount"`), 563 English shell keys and 483
  `I18n.t(` calls under `shell/`; a registry `default/i18n/locales.json`
  (`ar` = `ar_AE.UTF-8`, `"direction": "rtl"`, Western digits);
  `shell/Commons/I18n.qml` (`t(key, fallback)`, `tn`, `formatNumber`,
  `rightToLeft`; the language file `~/.config/omarchy/language` watched),
  `Plural.js` (CLDR categories; Arabic reaches all six) and `Numbers.js`;
  `shell/Commons/Translations.qml` for a plugin's own `i18n/<code>.json`.
- Right to left by `LayoutMirroring`: 38 uses under `shell/`
  (`git grep -c LayoutMirroring v4.5.0-rc1 -- shell`), set on each window's
  content (`shell/Ui/KeyboardPanel.qml:431`, `shell/plugins/notifications/Toast.qml:235`),
  with the media widget opted out (`shell/plugins/services/media/BarWidget.qml:199`).
- The catalogs are machine translations: the commit's trailers name "Muse"
  for every catalog and the manual (`git show -s 84cfb9395`).
- `bin/omarchy-language` writes the code, sets the session `LANG` in
  `~/.config/uwsm/env.d/50-omarchy-language`, pushes it into Hyprland
  (`hyprctl eval "hl.env(\"LANG\", …)"`, line 115) and restarts the shell; a
  missing locale is generated through a new passwordless sudoers rule,
  `etc/sudoers.d/omarchy-locale-generate`.
- 4.5-era plugins import `qs.Commons.I18n` and `qs.Commons.Translations`,
  which haseen's compat host lacked (`Compat/Omarchy/Commons/qmldir`, survey
  A.3 and A.6 #8): such a plugin failed to load.

## Design

### The singleton and the catalogs

`qs.Haseen.I18n` (`share/haseen/shell/Haseen/I18n.qml`) reads
`~/.config/haseen/language` (watched) as bash's `i18n_requested` does,
which `haseen language` and notifications use: the first line without one
leading UTF-8 BOM, one trailing CR (a file saved with CRLF) and surrounding
spaces and tabs, nothing more, so a hand-edited file is the same language
everywhere (review r2; `FileView`'s UTF-8 decoding drops the BOM in QML,
and eight shared cases in `tests/test-i18n.sh` hold all three to it). It
then reads, for a language other than
English, `share/haseen/i18n/<code>/shell.json` and `menu.json`, each read
whole and reassigned, so every binding that called `tr()` re-renders when the
language changes, without a restart. Its API:

- `tr(text, ...args)`: the translation of `text`, with `%1..%9` filled in one
  pass (Qt's chained `.arg()` would expand a `%2` inside the first argument).
- `tn(singular, plural, count, ...args)`: the counted form; `plural` is the
  key, `%1` the count in the language's digits. A fraction ("1.5 hours")
  takes the plural's `other` form in both languages, as CLDR says. A
  translation's `zero`, `one` or `two` form may leave `%1` out
  (لا توجد ترحيلات معلّقة); the checker requires the `other` form to keep
  the English placeholders and lets no form add one
  (`tools/i18n.py`, `check_value`).
- `mark(text)`: a no-op that marks English kept in QML data.
- `formatDate(date, format)` and `locale`: in English the same names as
  the code gave before. `main` named days and months with `Qt.formatDate()`
  (the lock screen's and the screensaver's date, the weather's day names)
  and `Qt.formatDateTime()` (the clock, the pager toast's day), both of
  which Qt 6 writes in English whatever `LANG` is; `formatDate` is
  `Qt.formatDateTime()` in English, which gives the same text for those
  formats. The calendar's month and weekday names and the weather's update
  time used the session's `Qt.locale()`, which `locale` is in English. In
  Arabic both use `ar_AE`, whatever `LANG` is. Checked offscreen under
  `LANG=de_DE.UTF-8`: `Qt.formatDate(d, "dddd, d MMMM")` and
  `Qt.formatDateTime(d, "dddd, d MMMM")` are both "Thursday, 22 October",
  `Qt.locale().dayName(4)` is "Donnerstag" (reviews r1 and r2).
- `formatNumber`, `rightToLeft`, `locale`, `language`, `languages`,
  `menuEntry(id)`, and `pick(entry, count, code)` for the compat host.

`share/haseen/shell/Haseen/I18nPlural.js` is Omarchy's `Plural.js` and
`Numbers.js` cut to the two languages haseen ships, plus the one-pass fill.

**Strings are keyed by their English**, not by invented ids as Omarchy does.
The code stays readable (`I18n.tr("Sign in to network")`), a string a
catalog lacks shows in English instead of a key, and an English string that
is reworded loses its old translation, which the checker then reports, rather
than keeping a translation of text that no longer exists. English needs no
catalog at run time. JS helpers (`.pragma library`, tested headless) keep
returning English and mark it `N_("…")`, defined in each such file; QML
translates the returned value. Plurals are `N_n`/`tn` with both English
forms written at the call.

Catalogs, in `share/haseen/i18n/`:

- `locales.json`: `en` and `ar` (name, English name, direction,
  `formatLocale`, `locale`, decimal separator, zero digit). Arabic is
  `ar_AE`, which gives Arabic day and month names with Western digits (Qt
  6: `Qt.locale("ar_AE").zeroDigit` is `"0"`, `ar`/`ar_SA`/`ar_EG` give
  `"٠"`, checked offscreen), as Omarchy chose.
- `<code>/shell.json`: the shell's strings, plus the catalogue's category
  labels (`share/haseen/default/catalog.json`) and the keybind sheet's bind
  descriptions and sections (`share/haseen/default/hypr/*.lua`), which are
  data the shell shows.
- `<code>/menu.json`: by menu id, `{label, title, description}`, applied to
  the shipped rows before the user's `menu.jsonc` overlay merges, so the
  user's own words win; the English label stays searchable
  (`searchTerms`), after Omarchy's `applyTranslations`.
- `<code>/notify.json`: the desktop notifications haseen's bash commands send.
- `en/*.json` are generated by `tools/i18n.py extract` from the code;
  `tools/i18n.py check` fails when they are stale, when another language
  lacks a string, changes its placeholders or lacks one of its plural forms,
  when a translation outlives its English, or when a QML text property holds
  bare English (`text: "Cancel"`; a line may say `// i18n-ignore`). Only
  literal strings are collected; a template literal or `+` in a key is
  refused.
- `ar/provenance.json`: `"translation": "machine"`, the translator, the date,
  a note, and the keys the owner has reviewed (none yet). `haseen language
  status` prints it.

### Right to left

`PanelPopup` mirrors every native panel's surface for Arabic
(`LayoutMirroring.enabled: I18n.rightToLeft && compat === ""`,
`childrenInherit`), which covers the menu, launcher and pickers too, since
they are panels. Plugins that own a window mirror its content themselves
(the toasts, OSD, lock, polkit and the other windows listed below). What is
**not** mirrored, and why:

- **The bar.** Its sections are the user's own arrangement (`bar.left`,
  `center`, `right`); flipping them would move every widget to the other
  side of the screen. Omarchy leaves its bar arrangement alone too. Bar
  widgets' labels and tooltips are translated.
- **Media transport and seek bars.** Previous/play/next and a playback
  position follow tape direction, not reading direction.
- **Time-series graphs**, colour strips whose order is data, keyboard maps.
- **Omarchy and DMS plugin panels**: they were written for left to right; a
  4.5-era plugin reads `Commons.I18n.rightToLeft` and can mirror itself.
- **Glyphs** are never flipped; directional ones (the menu's ›) are swapped
  by hand, and the menu's Left/Right keys follow the reading direction.

Sliders and level meters fill from the right (`TrackBar` reads its
inherited `LayoutMirroring`). Clock and number text needs nothing: digits
are a left-to-right run inside the Arabic line.

The per-plugin decisions are in "What each plugin mirrors" below.

### The command

`haseen language [en|ar|status|list]` (`bin/haseen-language`):

- `ar` writes `ar` to `~/.config/haseen/language` atomically
  (`replace_user_file`); the running shell switches at once; `en` removes
  the file (English is the default). Both notify, in the new language.
- `status` (the default) prints the language, its direction, the
  translation's provenance and review count, and the session locale. When
  they differ it says how to also run apps in Arabic (generate `ar_AE.UTF-8`
  with `locale-gen`, set `LANG` in `~/.config/uwsm/env.d/`) and that haseen
  does not do it.
- `list` prints the registry.

It changes no system file and asks for no privilege. Omarchy's
`omarchy-language` also sets `LANG`, which needs a generated locale and
therefore root (its NOPASSWD rule); changing `LANG` would also turn other
apps, `coreutils` errors and terminals Arabic, and most terminals do not lay
Arabic out right to left. So the session locale is proposed, not forced; the
owner can set it by hand. `language` joins the settings index
(`haseen settings list`, store `config`), and the menu gains Setup ›
Language with English and العربية rows (each language in its own name).
`haseen shell run` creates `~/.config/haseen` before qs starts, because a
watch needs its directory.

### Bash: notifications yes, terminal output no

The desktop interface is translated; terminal commands stay English. A
desktop notification is part of the desktop interface even when bash sends
it, so `share/haseen/lib/i18n.sh` gives bash `i18n "…"` and `i18n_n` (jq over
`notify.json`, the same English keys and plural rules, English when jq or
the catalog is missing; the values follow `--args --`, so one that looks
like a jq option, such as `-n` or `--help`, stays a value), and the
30-odd `notify-send` sites in `bin/` and
`share/haseen/lib/gestures.sh` use it. Everything a command prints in a
terminal, its errors and `--help` stay English, because:

- terminals mostly cannot shape or reorder Arabic (bidi), so an Arabic error
  would read broken exactly where it is needed;
- an English message is what a search, a bug report and the tests match;
- the commands' output is often read by scripts and by the shell itself
  (`haseen ... --json`, guards), which must not depend on the language.

### The compat host

`share/haseen/shell/Compat/Omarchy/Commons/{I18n,Translations}.qml`, adapted
from Omarchy's: the same API, with the language, direction and digits
haseen's. Omarchy's own keys read Omarchy's installed catalogs
(`$OMARCHY_PATH`, else `/usr/share/omarchy`), else the fallback a plugin
passes, else the key; a plugin's `Translations` reads only its own files.
Unlike Omarchy's, the compat `I18n` is a `Singleton` with child `FileView`s,
and both re-read on completion: a `FileView` made after the shell's load (a
plugin loaded late) or held as a property value did not read its file by
itself under Quickshell 0.3.2 (probed offscreen: the catalogs stayed empty
until a `reload()`, which then completes after the creating call returns).
haseen's own singleton does the same.

### Fonts

No new package. The base layer's `noto-fonts` (`extra`, installed through
`pkg_install`, `share/haseen/layers/base/packages.txt:14`) ships Noto Sans
Arabic and its UI cut, Noto Naskh Arabic (and UI) and Noto Kufi Arabic
(`pacman -Ql noto-fonts | grep -ci arabic`: 24 files); plan 047's fontconfig
lists Noto Sans Arabic and Noto Naskh Arabic after the theme's Latin family
(`share/haseen/themed/fonts.conf.tpl`), and Qt falls back through fontconfig
for glyphs the theme's family (Inter) lacks.

## What is translated

Counts are the catalogs' (`tools/i18n.py stats`): 1407 shell strings, 288
menu rows and 55 notification strings, all in `ar` (machine).

- **Every built-in plugin's panels and windows**, all 58 under
  `share/haseen/shell/plugins/`: labels, buttons, placeholders, tooltips,
  empty and error states, accessible names, and the strings JS helpers
  return (marked `N_`). Plugins that show only glyphs and numbers
  (active-window, idle, logo, nightlight, nook, power, workspaces) had
  nothing to route.
- **The menu**: the shipped rows of `share/haseen/default/menu.jsonc`
  (label, title, description, by id), the About facts, the provider rows
  (security, catalogue install/remove titles), and the commands provider in
  the launcher. The English label stays searchable.
- **The keybind sheet**: every description of the shipped binds and their
  sections (`share/haseen/default/hypr/*.lua`), including the four Lua
  builds at run time ("Workspace %1", "Move window to workspace %1", the
  silent move, the monitor moves), matched back to a key in
  `haseen.keybinds/Overlay.qml` (`describe()`).
- **Desktop notifications** that haseen's commands send: captures, toggles,
  hardware switches, reminders, transcode, migrations, the plugin URL
  handler, the boot-splash rebuild and the gestures (23 commands and
  `share/haseen/lib/gestures.sh`), plus the shell's own "%1 not loaded".
- **Dates** with names: the clock, the lock screen, the screensaver, the
  pager toast, the weather and omARR through `I18n.formatDate`, the
  calendar's month and weekday names through `I18n.locale`, in Arabic; in
  English they are as before (below). The prayers panel names its date in
  the prayer names' language, as it did.
- **Plans 105, 106, 108 and 110's strings**: per-monitor workspaces and the
  new binds, the captive-portal sign-in ("Sign in to network",
  "Sign-in required"), the agents' accounts, and the boot-splash
  notifications.

## What stays English

- Terminal output, errors and `--help` of every command (above).
- Data: app, window, device, network, track, file and theme names; command
  output a panel shows (the VAPT evidence, `haseen about`'s values); the
  user's own `menu.jsonc` rows and bind descriptions.
- Plugin manifest names and setting descriptions (`manifest.json`), shown
  only by the off-by-default plugin manager.
- IPC replies, console and journal messages.
- The greeter: it runs before login as the greeter user, who cannot read the
  user's language file.
- The catalogue's app names and descriptions.
- Service data inside panels: the security panel's evidence words
  (states, reasons, paths), omARR's and SABnzbd's status words
  (`downloading`, `queued`), Todoist's task text, VPN server names.
- `typist-worker.py`'s failure notifications (Python, outside
  `tools/i18n.py`), errors `haseen-prayers-zone.sh` writes, and the prayer
  engine's rare "could not assign prayer times to <date>", which is built
  from a date.
- Omarchy and DMS plugins' own strings, unless the plugin ships its own
  catalog (`Translations`) or Omarchy's catalogs are installed.

## English changes

The default desktop (no language file) reads as on `main` (review r1),
except these intended fixes, where a count of one used a fixed plural:

- clipboard "1 item" (was "1 items"); typist "1 byte · dd delete" and "over
  the size limit (1 byte)"; Wooting "1 column"; keybind sheet "1 binding —
  type to search"; browser picker "Offer a rule after 1 pick"; security
  (screen reader only) "Loaded 1 tool", "Loaded 1 installed service family";
  pager "Snooze for 1 minute", and "Snooze for 1 hour" for a custom length
  that rounds to one hour (61 or 62 minutes).

Kept as on `main` on purpose:

- The pager's custom snooze lengths from an hour on read in tenths of an
  hour as before ("Snooze for 1.5 hours", "2.5 hours"; exactly an hour is
  "an hour"). Arabic uses the same number with the plural's `other` form,
  which CLDR gives a fraction: تأجيل لمدة 1.5 ساعة. Under an hour both say
  minutes.
- Dates: see `formatDate` above. In English the lock screen, the
  screensaver and the weather's day names keep the names `Qt.formatDate`
  gave, the clock and the pager toast those of `Qt.formatDateTime` (the
  same English), omARR its English weekday names, and the calendar and the
  weather's update time the session's `Qt.locale()`; only Arabic forces
  `ar_AE`. The calendar's weekday heads switch to the locale's
  narrow names only when its two-letter heads collide (all of Arabic's
  start with ال); a session locale whose heads were distinct shows them as
  before.
- The prayer names: see "Open".

## What each plugin mirrors

Qt facts the work relies on, checked offscreen: `LayoutMirroring` flips
anchors, `Row`/`Grid`/`Flow`/`GridView` order and an *explicit* text
alignment; a `Text` with no alignment follows its own string (Arabic right,
Latin data left); a `Column` does not move a narrower child, and manual
`x` arithmetic is never mirrored. Hence the changes below.

**Mirrored by `PanelPopup` as they are**: bluetooth, syncthing, display
(its brightness rows use `TrackBar`), kblayout (a list of layouts, not a
key map), the launcher and its providers (commands, websearch, windows,
calculator, emojisearch). Every other native panel is mirrored the same
way and needed some of the changes below too.

**Own windows given a mirroring root**: the pager's toast deck, the
fallback notification popups, the OSD card, the lock view, the polkit
dialog, the screensaver view, the keybind sheet, the tray menu, the
indicators' and privacy dots' tooltips, the browser picker's card, the
prayers bar tooltip (in the prayer names' language). Windows stay where
they are (toasts top right, OSD bottom centre).

**Made mirror-aware by hand**:

- On/off switch knobs sit at the end edge when on: network, gestures,
  browser picker, omARR, prayers.
- Level fills grow from the start edge: OSD, audio volume rows, sysusage
  meters, wallhaven and omARR download progress, prayers' sliders and
  window bars, `TrackBar`.
- Grid arrow keys follow the screen: emoji, image picker, theme picker,
  background, themegen (and its Quick Look); the calendar's month arrows
  and Left/Right keys; the menu's Left/Right; omARR's detail pane keys and
  pager arrows; the security panel's back key (Right and l) and tab keys.
- Back and submenu arrows swap: the menu (› ‹), tray menu, calendar,
  security header, omARR pager.
- Items at `x: 0` or narrow children of a `Column` anchored to the start
  edge, so they move to the right: field placeholders (network, VPN,
  clipboard, settings, typist, browser picker, themegen, ai), pill rows
  (battery, updates, wooting, monitor settings, todoist and omARR settings),
  headings and buttons that overlapped their right-anchored siblings
  (network band header, ai author line, themegen title, weather rows,
  sysusage labels, security buttons and combo boxes).
- omARR and todoist set `AlignLeft` on their data labels so Latin data
  (task text, service names) follows the mirrored layout; in English the
  only change is that Arabic data is left-aligned too. The security panel's
  labels do the same.
- The calendar's weekday heads use the narrow names when the two-letter
  ones are not unique (every Arabic short name starts with ال).

**Kept left to right** (`LayoutMirroring.enabled: false`): the media
panel's seek column and transport, omaconnect's media transport, omARR's
playback position bars, the weather panel's temperature-and-unit row,
themepicker's palette strip, themegen's swatches and desktop mock, the
monitor arrangement map, the Wooting board, and the security panel's
dry-run output and review command. haseen.prayers keeps its own rule: its
panel and bar strip run in the prayer names' language, which follows the
interface by default.

Not changed on purpose: the bar and its widgets; clock digits (Western in
`ar_AE`); the gesture hints' physical arrows (Swipe ← →); key hints
(`h/j/k/l`, `Enter`, `Esc`) and the typist's vim keys; text fields holding
Latin data (passwords, addresses, paths, tokens).

**Every manual `x:` in the plugins, checked** (review r1; `grep -rnE
'^\s*x:\s|[{;]\s*x:\s' share/haseen/shell/plugins --include=*.qml`, 48
sites, plus `horizontalCenterOffset`, `mapToItem` and assigned `.x`):

- Fixed: the menu's brand mark (`haseen.menu/Panel.qml`) was at
  `x: space(8) + …`, so in Arabic it stayed left while the heading and the
  row icons moved right; it is now anchored (`left` + `leftMargin`) and
  sits over the icon column on the right.
- Symmetric insets, right as they are (a child at `x: m` whose parent is
  exactly `2m` wider, so mirroring would place it the same): the AI
  message column (`haseen.ai/MessageView.qml`, `x: pad`, width
  `width - 2·pad`); the background, theme picker and image picker cards
  (`x: Theme.gap` in a cell `cardWidth + 2·gap` wide); the emoji grid
  (`x: Theme.gap`, the panel `columns·cell + 2·gap`); the pager's sharing
  offer and text cards and the notification card's column; themegen's
  stage frames (`x: -pad`, `width + 2·pad`) and `StageFrame`'s column; the
  menu card, centred; the browser picker's click guard under its card.
- Already mirror-aware (they read `LayoutMirroring`): the switches
  (network, gestures, browser picker, omARR, prayers), `VolumeRow`,
  `PrayerSlider`, `GestureChoice`, the pager's held-list indent,
  `PagerButton`, toast title marks, omARR's scroll-mark gap, the security
  panel's check box and its card offset away from a vertical bar.
- Follow the text, not the layout, on purpose: the pager's reply field and
  send button (`isRtl` of what is typed).
- Positions read back, not set: the calendar's day-name row
  (`body.x + calendarGrid.x`, the grid's actual mirrored place), the menu
  row's hover point, `mapToItem` in the pager, tray, browser picker,
  security and monitor settings.
- Not mirrored by design: the bar's widgets (indicators, tray,
  workspaces), the toast deck's clipper (outside the deck's mirroring
  root), the screensaver's drifting card, the prayers horizon (the names'
  language), the monitor map, the Wooting board, themegen's desktop mock.

## Strings for the owner's review

All Arabic is a machine translation. These are the ones the translators were
least sure of:

Grouped by kind; each line is the English key, the Arabic chosen, and why
it is uncertain.

**Vocabulary to settle once** (one key, used across panels):

- "Trigger" → تشغيل سريع (menu: the quick-action section), "Style" →
  المظهر, "Setup" → الإعداد, "Learn" → تعلّم.
- "Snooze" → تأجيل, "Snoozed until %1" → مؤجَّلة حتى %1 (Apple's Arabic
  uses غفوة for alarms); "%1 held", "HELD BACK" → محتجز/المحتجزة.
- "On"/"Off" → تشغيل/إيقاف everywhere, also as the settings filter chip
  where المفعّلة would read better; plugin states "enabled", "disabled",
  "unmet" → مفعّلة، معطّلة، متطلبات غير مستوفاة.
- "Wrong password" → كلمة المرور غير صحيحة (two translators differed);
  "Empty" → فارغ; "Scratchpad" → المسودة (the lock screen, the workspace
  widget and the keybind sheet share the key); "%1 left" → المتبقي %1.
- "Snooze for %1 hours" with a fraction: تأجيل لمدة 1.5 ساعة (the `other`
  form); minutes (90 دقيقة) would avoid the decimal.
- Compact units: "%1m"/"%1h"/"%1s"/"%1d" → %1 د/س/ث/ي (pager, agents,
  omARR, sysusage); full words would need plurals and room. ي for يوم is the
  least established.
- "Kill switch" → مفتاح القطع, "Lockdown mode" → وضع الإغلاق, "Relay" →
  الخادم, "Post-quantum VPN" → VPN ما بعد الكم.
- "tray" → شريط النظام; "widget" → أداة; "the shell" → الواجهة;
  "firmware" → البرنامج الثابت; "anchor" (a CA trust anchor) → مرساة;
  "entrypoint" → نقطة دخول; "provisioning" → التجهيز.

**Playful or idiomatic English rendered by meaning**:

- The network hero's rotating phrases ("Wiring bits", "Handling packets",
  "Bending light", …) as first-person verbs (نوصّل البتات …).
- The audio panel's volume names ("Concert hall", "Cranked up", "Murmur",
  "Whisper", …) → قاعة حفلات، صاخب، همهمة، همس.
- Todoist's "Nothing due. You're clear." → لا شيء مستحق. لا مهام عليك.;
  omARR's "Queue is quiet." → لا شيء في قائمة الانتظار; "FLEET" →
  الخدمات; "ON DECK" → متابعة المشاهدة; "%1 grabbed" → جلب %1.
- Material You scheme names ("Tonal spot", "Fruit salad", "Expressive", …)
  translated literally; they could stay Latin.

**Grammar the template constrains**:

- "Connecting to %1…" → جارٍ الاتصال بـ%1… reads oddly when %1 is a
  translated phrase with its article ("بـأسرع خادم").
- "Up to date · %1 of %2 devices" reworded (الأجهزة المتصلة: %1 من %2) so
  the count needs no agreement; "… and %1 more" → … و%1 غيرها; moon age
  "%2 days old" keeps يوم singular because the age is a decimal.
- Zero and two forms that are never shown in practice ("Offer a rule after
  %1 picks" at 0, "Press again to delete %1 plugins" under 2).
- Notification titles with a service as subject ("%1 added" → أضاف %1,
  "%1 is down" → توقّف %1): masculine agreement with the product name.

**Bidi marks inside translations** (U+200E LRM, U+200F RLM), each checked
in a rendered panel or chosen deliberately:

- LRM before `/theme`-style commands in the launcher's help, before
  `~/.local/state` in Todoist's token hint, and before `%1` in the security
  panel's "FragmentPath: %1", "Issuer: %1" and "Exit code: %1" lines, so a
  path or number does not jump to the wrong end.
- RLM at the start of Todoist's key list lines and omARR's "%1 idle", and
  Arabic-first rewordings ("Caps Lock on" → مفتاح Caps Lock مُفعّل,
  Todoist's bar tooltips), so a line whose first letter would be Latin
  still runs right to left.
- "dddd, d MMMM" (lock and screensaver date) is a Qt format string in the
  catalog: → dddd، d MMMM, with an Arabic comma; its letters must stay.

**Technical terms kept Latin on purpose**: Wi-Fi, Bluetooth, VPN, Ping,
CPU, PID, JSON, PAM, CA, SHA-256, loopback, doctor (the security command),
product and command names, and `services` where it names a shell.json key.

## Rejected options

- **Omarchy's dotted keys** (`I18n.t("network.signIn")`): every call site
  needs a lookup to read, an English catalog has to be written by hand, and
  a missing key shows as a key. Keyed by English, the code is its own
  English catalog.
- **Qt's `qsTr` and `.qm` files**: needs `lupdate`/`lrelease` in the build
  and a `QTranslator` installed in the engine, which Quickshell does not
  expose; a live switch would need `retranslate()`.
- **Reusing Omarchy's Arabic catalogs**: different keys and strings, and
  machine-made too; haseen's are written for its own strings and marked as
  machine-made.
- **Setting `LANG` from `haseen language`**, as `omarchy-language` does:
  needs root for `locale-gen` (the owner did not take Omarchy's NOPASSWD
  rule) and turns every app and terminal Arabic. Proposed in `status`
  instead.
- **Translating command output**: see "Bash" above.
- **Mirroring the bar**: see "Right to left".
- **Mirroring compat plugins' panels**: they were not written for it.
- **One catalog per plugin** (`plugins/<id>/i18n/`, like `Translations`):
  58 more files to watch and load; one `shell.json` per language is one read.

## Tests and gates

All runs hermetic (offscreen Qt, no Wayland/Hyprland/D-Bus session, a
private `XDG_RUNTIME_DIR` and `TMPDIR`, `HASEEN_REQUIRE_ENGINE=1`), on
2026-10-22, against `origin/main` at `6cdaf97`:

- `tests/run.sh` with the `tools/affected-tests.sh` selection: 97 of 163
  test files. 96 ran in four chunks of 24 under short bind-mounted paths
  (sockets in long paths overflow): 2726/2726, 2543/2543, 2293/2293,
  3173/3173, so **10735/10735**; `test-capture-upload.sh` with
  `test-i18n.sh` outside the bind mount: **434/434**.
- `tests/test-i18n.sh` alone: **76/76** (catalog checks, the checker on a
  fake tree, bash `i18n`, `haseen language`, and the real engine: `tr`,
  plurals, dates, the menu catalog, the compat `I18n`/`Translations`, a
  mirrored `TrackBar` and menu row).
- After review r1, the same selection again (97 files): four short-path
  chunks 3635/3635, 2205/2205, 2755/2755, 2148/2148, so **10743/10743**
  (the eight more are `test-i18n.sh`'s new checks: values `-h`, `-n`,
  `--help`, `-e`, `--` and a plural with option-like values in Arabic
  notifications; the language file's first line in bash, `haseen language
  status` and the shell; English dates under `LANG=de_DE.UTF-8`, Qt's
  English names from `formatDate` and "Donnerstag" from `locale`, Arabic
  ignoring `LANG`; a fraction's plural form in both languages), and
  `test-capture-upload.sh` outside the bind mount: **358/358**;
  `test-i18n.sh` alone **84/84**. `tools/lint.sh`, now with
  `tools/i18n.py check`: lint OK.
- After review r2, merged with `origin/main` at `bc2f6e1` (#67, plan 111;
  no conflicts, no new desktop string): the same 97 files against the new
  main, four short-path chunks 3665/3665, 2205/2205, 2755/2755, 2174/2174,
  so **10799/10799** (24 more in `test-i18n.sh`, now **108/108**: eight
  CRLF/BOM/blank cases each for bash, `haseen language status` and the
  shell; the rest is plan 111's own), `test-capture-upload.sh` outside the
  bind mount **358/358**, `tools/lint.sh` lint OK.
- The first commit on its own (core, menu, bash): `test-i18n`,
  `test-settings`, `test-menu`, `test-menu-view`, `test-menu-radius`,
  `test-menu-back`, `test-core`, `test-keybinds`: **880/880**.
- While converting, each plugin group ran its own tests (network-panel,
  widgets-a/b/c, omaconnect, syncthing, pager, notification, lock,
  keyboard, indicators, surfaces, audio-panel, battery, media, wooting and
  its `model.test.js`, launcher-providers, themegen, monitor-settings,
  omarr 49/49, todoist 61/61, prayers 42/42, the VAPT security suites and
  others); all pass in the final run above.
- `python3 tools/i18n.py check`: fresh and complete for `en`, `ar`
  (1407 shell, 288 menu, 55 notify).
- `tools/affected-tests.sh --check`: 2649 files, 163 tests, 1889 covers
  globs, every file covered, global or exempt.
- `tools/check-docs.sh`: OK.
- `tools/lint.sh` (`SHELLCHECK=/usr/bin/shellcheck`): lint OK (912 shell,
  36 Lua, 206 JSON, 337 QML and 41 Go files).
- `gitleaks git --log-opts=6cdaf97..HEAD` over the branch's commits: no
  leaks; the privacy grep (tailnet addresses, home paths) over the same
  range: nothing. `tools/secrets.sh` exits 1 with the same six gitleaks
  findings and the same home-path fixture lines (an omARR art path, a VPN
  profile) on `origin/main` as on this branch: they predate it.
- `grep -rn 'sudo ' bin share | grep -v common.sh`: no new call; the new
  hits are the VPN panels' existing hint text, now also in the catalogs.

## Not verified

- A live Arabic session: everything above ran offscreen in Quickshell's real
  engine (the singleton, plurals, dates, the menu catalog, the compat
  types, a mirrored `TrackBar`), but no panel was looked at in Arabic on a
  real compositor, so clipping, Arabic line height in a 28 px bar and the
  mirrored panels' look are unproven.
- Native-reader quality of the Arabic.
- The first frame after the shell starts in Arabic (or after a switch) can
  show English: the catalogs are `FileView`s whose first read completes
  just after the singleton is created (Quickshell 0.3.2, see "The compat
  host"), and bindings re-render when it lands. A synchronous read at
  creation is not available to a lazily created singleton, so this stays.

## Owner steps

1. Review the Arabic: `share/haseen/i18n/ar/{shell,menu,notify}.json`,
   starting with the list above. Edit a string in place; add the keys you
   approve to `reviewed` in `ar/provenance.json` (and set `translation` to
   `partly reviewed` or `reviewed`). `tools/i18n.py check` keeps the files
   honest.
2. On IO or luna after the update: `haseen language ar`, open the menu
   (SUPER + SPACE), a few panels (network, audio, battery, calendar), a
   notification, the lock screen and the keybind sheet (SUPER + F1); then
   `haseen language en`. Look for clipped Arabic in the bar and panels.
3. To also run apps in Arabic (optional): generate `ar_AE.UTF-8` in
   `/etc/locale.gen` with `locale-gen`, put `export LANG=ar_AE.UTF-8` in
   `~/.config/uwsm/env.d/50-language`, and log in again.
4. Digits: `ar` uses Western digits (`zeroDigit` `"0"` in
   `share/haseen/i18n/locales.json`); set `"٠"` there for Arabic-Indic.

## Open

- Arabic-Indic digits: one value in `locales.json`, not exposed as a
  command; ask if wanted.
- The menu's Setup › Language checkmark still compares the file's raw
  first line (`head -n1` in `share/haseen/default/menu.jsonc`), so a
  hand-edited CRLF or BOM file can tick English while the interface is
  Arabic; `haseen language` always writes a clean file. Normalising it
  there means a third copy of `i18n_requested` in a menu guard.
- haseen.prayers changed its default: its names now follow the interface
  language (setting `language`, default `Interface`); it was `English`
  (`plans/026-haseen-prayers.md`). For an English interface nothing
  changes; with Arabic chosen, the prayer names turn Arabic too. Forcing
  English or Arabic stays possible.
