# Plan 141: One font and one type scale for every plugin

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM. 379 size lines in 112 files change. Most keep
  their pixel size at the default base of 12. Some move by one or two pixels
  onto the nearest role, and the menu and launcher cards lose the 9% that a
  stale base of 11 added. Third-party bar widgets change size by design.
- **Depends on**: 068 (haseen.menu), 115 (Omarchy 4.5's tokens, base 12),
  122 (MenuMetrics)
- **Category**: shell
- **Planned at**: 2026-10-27
- **State**: DONE 2026-10-27. Test results:
  - `tests/test-shell.sh` 283/283;
  - `tests/test-compat-font.sh` 28/28;
  - `tools/fonts.py check`: 264 files, one family, one scale;
  - `tests/run.sh --affected`: 68 files, 6153/6153 after merging main
    with plan 140. The security suites
    (`test-vapt-panel-conformance`, `test-vapt-security-ui`,
    `test-vapt-ui-adversarial`, 222/222) needed the type scale in their
    stand-in `Theme` (`tests/fixtures/vapt-qml-lib.sh`). The run is from a
    short path: from a long worktree path `test-menu-back`'s quickshell
    socket path exceeds the 108-byte limit.

## Problem

Owner, 2026-10-27:

> make the plugins have the same font size and same font

Asked how far that should reach, the owner chose "haseen + compat override
(Recommended)". haseen's own plugins move to one type scale and one family.
The compat layer draws every third-party bar label at the bar's size and in
the bar font, whatever the plugin asks for. The owner's plugin files stay as
they are (CLAUDE.md, "Never remove the owner's plugins").

Plan 115 (70ac0c4) gave haseen Omarchy 4.5's type scale: `Theme.font`
`caption`, `bodySmall`, `body`, `subtitle`, `title`, `heading`, `display`,
`displayLarge`, `icon` and `iconLarge`. They are 10, 11, 12, 13, 14, 16, 24,
28, 14 and 18 px at the default base of 12. These are Omarchy's
`Commons/Style.qml:328-339` values. Most plugins never used them:

- **Offsets from the base size.** On origin/main the built-in plugins drew
  text at 372 `Theme.fontSize` expressions (see Evidence for the count):

  | Expression | Sites |
  |---|---|
  | `Theme.fontSize` | 144 |
  | `Theme.fontSize - 1` | 86 |
  | `Math.max(1, Theme.fontSize - 1)` | 42 |
  | `Theme.fontSize + 2` | 32 |
  | `Theme.fontSize - 2` | 12 |
  | `Math.max(1, Theme.fontSize - 2)` | 8 |

  The other 48 were hero sizes such as `* 2`, `* 3`, `* 4.5`, `+ 3`, `+ 5`
  and `+ 6`, which varied from plugin to plugin. A battery percentage, a weather temperature and a pager
  bell were each a size of their own.
- **A stale base of 11.** The menu (`MenuStyle.js` `scale()`), the launcher
  (`Haseen/MenuMetrics.qml`) and `haseen.security` still divided by 11, a
  rule written when 11 stood for Omarchy's 12 (e3070bd, de8a8fe). Plan 115
  made 12 the base, so these surfaces drew body text at 13 px against 12
  everywhere else. The menu card was 327 px wide where Omarchy's is 300
  (plan 115, "Menu-style card ... after 327x636").
- **No family.** Three text elements set no `font.family`, and the shell sets
  no application font, so they fell back to the system sans:
  - the emoji grid, `haseen.emoji/Panel.qml`;
  - the gesture and prayer dropdown chevrons, `GestureChoice.qml` and
    `PrayerDropdown.qml`.
- **Third-party bar widgets choose their own sizes.** The owner's bar on luna
  shows these Omarchy plugins next to haseen's widgets:

  | Plugin | Draws at |
  |---|---|
  | `t1nk33r.nettraf` | `Style.font.caption` (`BarWidget.qml:135`) |
  | `t1nk33r.openvpn-ip` | `Style.font.caption` (`BarWidget.qml:344`) |
  | `t1nk33r.omaprayers` | `Style.font.bodySmall`, label and countdown (`BarWidget.qml:147`, `:240`) |
  | `t1nk33r.todoist` | `Style.font.bodySmall`, its task count (`BarWidget.qml:193`) |

  haseen's own bar draws every label at `Theme.font.body`. Omarchy's own bar
  is not uniform either: KeyboardLayout and SystemUpdate use `caption`, and
  Tray uses `bodySmall` (`/usr/share/omarchy/shell/plugins/bar/widgets/`).
- **Two icon sizes in one bar.** haseen's bar glyphs were `Theme.font.icon`,
  14 px (`Widgets/Glyph.qml`). Omarchy's bar icons, and the Omarchy plugins
  that follow them, are `Style.bar.iconFont`, 13 px: see Omarchy's
  `Ui/BarIconButton.qml:19`, and `t1nk33r.updates` and `t1nk33r.nook` (both
  `fontSize: Style.bar.iconFont`).

## Decision

One family and one scale, enforced by a checker, and the bar's sizes forced
on third-party bar text at run time.

### haseen's own shell

Every built-in text size is a `Theme.font` token, or a property holding one.
The mapping keeps each site's pixel size at base 12 where a token has that
size:

| Before | After |
|---|---|
| `Theme.fontSize` | `body` |
| `- 1` | `bodySmall` |
| `- 2` | `caption` |
| `+ 1` | `subtitle` |
| `+ 2` | `title` |
| `fontPx(m)` | the token of multiplier `m` |

`- 3` (9 px) becomes `caption` (10 px), the smallest token. Hero sizes take
their Omarchy role:

- **`display`** for a panel's hero glyph or number (PanelHero's icon role):
  the battery, media, network, weather, todoist, omarr and omaconnect
  heroes, the pager bell, the calendar card, the theme picker's "Aa"
  sample and the overlay template.
- **`title`** for a hero's name and its unit (PanelHero's title).
- **`icon`** for the forecast glyphs and the omarr button glyph.
- **`heading`** and **`title`** for the OSD card's value and icon, which
  were `* 1.6`, `* 1.4` and `* 1.2`.

A size that depends on a condition chooses between tokens:

- the sysusage bar text: `vertical ? caption : body`;
- the wooting key caps: long labels `caption`;
- the typist rows: headers `body`, entries `bodySmall`;
- the menu's About brand: `caption` for a multi-line logo, `display`
  otherwise.

The menu and the launcher scale by `Theme.fontScale` (base 12) and draw
headings at `Theme.font.heading` and row icons at `Theme.font.iconLarge`.
Omarchy's `Menu.qml:1245` draws them at `Style.font.iconLarge`. The menu card
is Omarchy's 300 px again. `haseen.security` drops its own `/11` scale: its
fields are `body`, its labels `title` or `body`, and its widths
`Theme.fontScale`.

The bar draws icons at `Theme.barMetrics.iconFont` (Omarchy's
`Style.bar.iconFont`), both in `BarButton` and in `haseen.sysusage`. So a
haseen glyph and an Omarchy plugin's icon now share one size. Labels stay at
`Theme.font.body`.

Some sizes are exempt from the scale, marked `// fonts-ignore: <why>`:

- **Full-screen surfaces**, which scale with the screen:
  - the lock's clock, its field and its password dots (sized like hyprlock's);
  - the screensaver's branding, clock and date.
- **haseen.omarr's fallback letter**, which fills its tile at any tile size.
- **The emoji grid**, whose glyphs need the colour emoji face: a monospace
  primary family splits ZWJ sequences. It is drawn at `display`.
- **haseen.pager's toast**, multiplied by the pager's own `fontScale`
  setting. At its default of 1 its sizes are the tokens.
- **haseen.prayers' `arabicFont` setting** (Noto Naskh Arabic): Arabic names
  need a face with Arabic glyphs. The marker sits at the property's
  definition, so it covers every use.

`Theme.fontSize` remains in layout geometry, such as panel widths and row
heights in multiples of the base size. That scales with the font, which is
the intent, and the checker does not look at it.

### The checker, `tools/fonts.py`

`tools/fonts.py check` enforces this. It covers `share/haseen/shell/*.qml`,
`Haseen/` except `Theme.qml`, `plugins/` and `templates/`. It skips
`Compat/`, whose components are Omarchy's and DMS's, and `greeter/`. It
fails when any of these is true:

- a text element sets no family or no pixel size. It accepts `font:
  other.font`, and a type with a `.qml` of the same name beside it is a
  local component;
- a `font.family` or `font.pixelSize` assignment does not resolve to a theme
  token. The checker follows property references through:
  - the singleton a qualified reference names (`MenuMetrics.iconSize`);
  - otherwise the same file, the same directory, then anywhere;
- an assignment in JavaScript (`label.font.pixelSize = …`, or a logical
  one such as `??=`) does not resolve to a token, or is arithmetic (`+=`,
  `++`), which is relative by nature;
- `font.pointSize` is used.

Before it looks, the checker blanks comments and masks strings and regex
literals, keeping every offset and newline. A regex is told from a division
by what precedes the `/` (an operator, a bracket or a keyword such as
`return`), and it ends at its line, as a regex cannot hold a newline. A QML
string may span lines (`Haseen/Apps.qml:26-35` holds a shell script), so a
string runs to its closing quote; a quote that nothing closes before the end
of the file is not a string and ends at its line, so one stray quote cannot
hide the rest of a file.

`tools/lint.sh` runs it after `i18n.py`, and `tests/test-shell.sh` asserts it
passes over the tree. The same test checks a fixture of known breaches:
arithmetic on the base size, a missing family, a literal family,
`pointSize`, a missing pixel size, breaches after a regex that holds a
quote, after a regex line that ends in a backslash and after a quote that
never closes, and sizes assigned in JavaScript, including `++` and `||=`. It
also checks that a token-holding property, a condition between tokens, an
exempt definition, `font: other.font`, a theme family assigned in
JavaScript (with `=` or `??=`) and text inside a string over several lines
pass.

### Third-party bar widgets, `Compat/BarFonts.qml`

Both bar hosts give their widget to `BarFonts`: `OmarchyHost` for a
`bar-widget` entry and `DmsHost` for a pill. `BarFonts` walks the widget's
visual children, which are what the bar shows. A plugin's popout is a
`PopupWindow` of its own, outside the walk: see
`Compat/Omarchy/Ui/PopupCard.qml:10` and
`Compat/Dms/Modules/Plugins/PluginPopout.qml`. For each child:

- **A qs.Ui `WidgetButton` with a bar** adopts the bar's size through
  `adoptBarFont()`:
  - its `fontSize` is rebound to `Theme.font.body`, or to
    `Theme.barMetrics.iconFont` for an icon-only label;
  - its `fontFamily` is rebound to the bar font.

  Because `fontSize` itself changes, a plugin that reserves width with a
  `TextMetrics` at `button.fontSize` (nettraf, openvpn-ip) measures what is
  drawn. Its icon-only labels keep the "Symbols Nerd Font" rule from plan 049.
- **A `Text` inside a component that owns a `fontSize`** follows that
  `fontSize` as the plugin bound it. Examples are the label of a
  `WidgetButton` without a bar (a plugin's inner helper) and qs.Ui's
  `OpticalGlyph`. Plugins bind these to their button's size, which the bar
  now sets. `agx.screen-time`'s vertical lines are `OpticalGlyph`s at
  `button.fontSize`, squeezed to 0.9 of it for long values (`BarWidget.qml:257`);
  they keep the squeeze.
- **Any other `Text`** (a `Label` is one) takes the icon size when it shows
  only Nerd Font icons and the text size otherwise. Icons include the
  supplementary private-use plane, the nf-md set, as surrogate pairs. Its
  family becomes the bar font, with two exceptions that keep the family the
  plugin gave them:
  - icons;
  - text in a script the bar font may lack: Arabic, Hebrew, Indic, Thai,
    CJK and Hangul.

The bindings follow the text, so a label that turns into an icon resizes.
Children that appear later (a Loader's item, a Repeater's delegate) are
walked when `childrenChanged` reports them, through `Qt.callLater`. There is
no timer (architecture 6). Each walk rebuilds the set of items it adopted,
so one no longer in the tree (a delegate a Repeater dropped) is forgotten
and the set does not grow with a churning model. An item that leaves and
comes back is adopted again with a single `childrenChanged` connection: it
is disconnected before it is connected.

The engine scenario in `tests/test-compat-font.sh` builds such a widget in
Quickshell. It checks that:

- a caption `WidgetButton` draws at 12 px in the bar font;
- an icon button draws at 13 px;
- an unbound helper follows its owner at 6 px;
- a `Text` in a component whose `fontSize` is the owner's minus 2 draws at
  10 px;
- a raw caption `Text` draws at 12 px in the bar font, and at 13 px once its
  text is an icon;
- an nf-md glyph draws at 13 px and keeps "Symbols Nerd Font";
- Arabic draws at 12 px and keeps Noto Naskh Arabic;
- a Loader's late `Text` is adopted;
- a Repeater's delegates are adopted, and the two it drops when its model
  shrinks from 3 to 1 leave the set;
- a `TextMetrics` at `button.fontSize` reads 12;
- a `Text` outside the visual tree stays at 7 px.

## Rejected

- **Editing the owner's plugins to use `Style.font.body`.** CLAUDE.md forbids
  rewriting anything in `~/.config/omarchy/plugins/`. Patched copies would
  also drift from their upstreams.
- **A compat `Style` whose tokens all return `body` inside the bar.** `Style`
  is a singleton shared by a plugin's bar widget and its panel, so the
  panels' hierarchy (titles, captions) would collapse too.
- **Scaling `fixedWidth` by the ratio of the bar size to the requested
  size.** Rebinding `fontSize` makes the plugins' own measurements correct,
  and a ratio would misplace widths set from their own text metrics.
- **Leaving haseen's bar glyphs at `Theme.font.icon` (14) and forcing
  plugin icons to 14.** Omarchy's bar icon size is `Style.bar.iconFont`.
  Matching Omarchy keeps the owner's "make it look like omarchy" direction
  (plan 115).
- **Overriding the family of icons and Arabic text.** An icon's face decides
  its advance (plan 049). The bar font has no Arabic, so Arabic in it would
  reach a fontconfig fallback instead of the face the plugin chose.

## Evidence

The counts come from `git diff origin/main -U0 -- share/haseen/shell`.
Lines holding `font.pixelSize`: 379 added, in 112 files, and 376 removed.
Of the removed lines, 372 held a `Theme.fontSize` expression. Problem's
table counts each removed value, the text after `font.pixelSize:`, exactly
as written.

| Case | Before | After |
|---|---|---|
| Stale /11 rule | `MenuStyle.js:26` `fontSize / 11`; `MenuMetrics.qml:15` `Theme.fontSize / 11`; `haseen.security` `Math.round(12 * Theme.fontSize / 11)` in `Field.qml`, `GroupFilter.qml` and `SelectableText.qml` | `Theme.fontScale` and `Theme.font.body` |
| Omarchy's tokens | `/usr/share/omarchy/shell/Commons/Style.qml:328-339` | caption 10 to iconLarge 18 at base 12 |

Engine probe output from the scenario above. The test runs in a hermetic
home, so the bar font is the theme's default, JetBrainsMono Nerd Font:

```
{"body":12,"icon":13,"mono":"JetBrainsMono Nerd Font","cell":12,"cellFamily":"JetBrainsMono Nerd Font","iconCell":13,"helper":6,"squeezed":10,"small":12,"smallFamily":"JetBrainsMono Nerd Font","smallIcon":13,"glyph":13,"glyphFamily":"Symbols Nerd Font","arabic":12,"arabicFamily":"Noto Naskh Arabic","late":12,"metrics":12,"detached":7,"repeated":12,"pruned":true}
```

## Residual

- A plugin that reserves width with a `TextMetrics` at a size of its own
  (memvram's `iconSize`/`valueSize` settings) is measured at that size. At
  memvram's defaults (`Style.bar.iconFont`, `Style.font.body`) these are the
  bar's sizes. An owner setting that shrinks them would reserve less than is
  drawn.
- A component of the plugin's own that owns a `fontSize` property keeps
  the size the plugin gives it. The walker cannot tell a squeeze relative to
  the button from a fixed smaller size, and plugins bind these to their
  button.
- Panels of third-party plugins are untouched. They use Omarchy's `Style`
  tokens, which are haseen's scale already (plan 115).
- A plugin that sets a size in JavaScript after `BarFonts` adopted the item
  (`button.fontSize = 9` in a handler) replaces the binding, and that size
  stays. Declarative bindings are replaced by `BarFonts`'. No built-in
  plugin and none of the owner's (a grep of `~/.config/omarchy/plugins` and
  `~/.config/DankMaterialShell/plugins` on 2026-10-27) assigns a size in
  JavaScript.
- `iconOnly()` knows the private-use areas only. An icon outside them (the
  power symbols at U+23FB to U+23FE, an emoji) counts as text: 12 px in the
  bar font, so a colour emoji reaches its face through fontconfig's
  fallback.
- The checker resolves a bare property name, when neither its file nor its
  directory defines it, from any file in scope. An unrelated property of the
  same name that holds a token would satisfy it. The reviewer found no case
  in the tree.

## Review

Round 1 (DeepSeek V4.1 Flash, head 0735808, REQUEST_CHANGES):

1. **A quote in a regex literal hid the rest of a file from the checker.**
   `mask()` treated `/^["']?…/` as opening a string, which ran to the end of
   the file. `haseen.themepicker/ThemeCard.qml` hid two sizes this way, the
   "Aa" sample at `Theme.fontSize * 2` and the theme name at
   `Theme.fontSize`. Fixed: `mask()` knows regex literals and ends an open
   quote at its line, and the two sizes are `display` and `body`. The
   fixture's `Regex.qml` fails without the fix (the old checker passed it
   as "1 files, one family, one scale").
2. **A size set in JavaScript after adoption escapes `BarFonts`.** Recorded
   in Residual. Re-asserting the binding on every change would fight the
   plugin.
3. **`_seen` never shrank.** Fixed by rebuilding it on every walk rather
   than a `WeakSet`: the walk already visits every item, a rebuilt set drops
   an item as soon as it leaves the tree rather than at garbage collection,
   and its size is observable, so `tests/test-compat-font.sh` checks it. A
   destroyed item's `childrenChanged` connection goes with the item.
4. **The checker missed assignments in JavaScript, and its "anywhere"
   lookup can be satisfied by an unrelated file.** The first is fixed (see
   the checker above); the second is in Residual.
5. **The plan's numbers did not reproduce.** They are recounted from the
   current diff, and Evidence gives the method. The reviewer's 377 lines in
   111 files plus the two `ThemeCard.qml` lines are the 379 in 112.
6. **Icons outside the private-use areas, and CJK outside the BMP.**
   `otherScript()` now covers U+20000 to U+2FFFF; the icons are in Residual.

The reviewer also observed that the largest changes are heroes: the weather
temperature 54 and 48 to 24, battery and media 36 to 24, network 29 to 24,
omarr and omaconnect 18 to 24, the forecast icon 24 to 14, and the OSD 19
to 16. All follow the role table above. They are Omarchy's `display` size,
and the owner can ask for a larger hero role.

Round 2 (DeepSeek V4.1 Flash, head 13ca856, APPROVE), checked by running
(6115/6115 on the affected selection; a breach appended to each of the 264
files, and after every line holding a `/`, was reported everywhere but under
`fonts-ignore`), with four nits, all taken:

1. **A QML string may span lines**, and `Haseen/Apps.qml:26-35` does, so
   ending a quote at its line parsed that script as code, and the docstring
   and this plan said otherwise. A string now runs to its closing quote;
   only a quote that nothing closes ends at its line.
2. **A backslash at a regex line's end** carried the regex onto the next
   line. A regex now ends at a newline, escaped or not.
3. **An item that left the tree and came back connected `childrenChanged`
   again.** `Qt.callLater` collapsed the extra calls, so nothing showed;
   the item is now disconnected first, which a probe showed is a no-op when
   it was not connected.
4. **`++`, `--`, `||=`, `&&=` and `??=` were not matched.** The first two
   are reported as relative; a logical assignment's value is checked like
   `=`, since it either keeps a value already checked or assigns this one.

`tests/test-shell.sh`'s `Edges.qml` covers 1, 2 and 4; the round-2 checker
fails five of its asserts.
