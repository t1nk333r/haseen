# Plan 141: One font and one type scale for every plugin

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MEDIUM. About 390 size lines in 120 files change. Most keep
  their pixel size at the default base of 12. Some move by one or two pixels
  onto the nearest role, and the menu and launcher cards lose the 9% that a
  stale base of 11 added. Third-party bar widgets change size by design.
- **Depends on**: 068 (haseen.menu), 115 (Omarchy 4.5's tokens, base 12),
  122 (MenuMetrics)
- **Category**: shell
- **Planned at**: 2026-10-27
- **State**: DONE 2026-10-27. Test results:
  - `tests/test-shell.sh` 270/270;
  - `tests/test-compat-font.sh` 26/26;
  - `tools/fonts.py check`: 264 files, one family, one scale;
  - `tests/run.sh --affected`: 68 files, every test passes. The security
    suites (`test-vapt-panel-conformance`, `test-vapt-security-ui`,
    `test-vapt-ui-adversarial`, 222/222) needed the type scale in their
    stand-in `Theme` (`tests/fixtures/vapt-qml-lib.sh`). `test-menu-back`
    (34/34) passes when run from a short path: from a long worktree path its
    quickshell socket path exceeds the 108-byte limit.

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
  text at 370 `Theme.fontSize` expressions (`git diff origin/main` of this
  branch):

  | Expression | Sites |
  |---|---|
  | `Theme.fontSize` | 143 |
  | `Theme.fontSize - 1` | 86 |
  | `Math.max(1, Theme.fontSize - 1)` | 42 |
  | `Theme.fontSize + 2` | 32 |
  | `Theme.fontSize - 2` | 12 |
  | `Math.max(1, Theme.fontSize - 2)` | 8 |

  Hero sizes such as `* 2`, `* 3`, `* 4.5`, `+ 3`, `+ 5` and `+ 6` varied from
  plugin to plugin. A battery percentage, a weather temperature and a pager
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
  heroes, the pager bell, the calendar card and the overlay template.
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
- `font.pointSize` is used.

`tools/lint.sh` runs it after `i18n.py`, and `tests/test-shell.sh` asserts it
passes over the tree. The same test checks a fixture of known breaches:
arithmetic on the base size, a missing family, a literal family,
`pointSize`, and a missing pixel size. It also checks that a token-holding
property, a condition between tokens and an exempt definition pass.

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
no timer (architecture 6).

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

The scale on origin/main came from `git diff origin/main -U0 -- share/haseen/shell`,
counting `font.pixelSize` lines: 394 added lines, 370 of them replacing a
`Theme.fontSize` expression. The tallies in Problem come from the same diff.

| Case | Before | After |
|---|---|---|
| Stale /11 rule | `MenuStyle.js:26` `fontSize / 11`; `MenuMetrics.qml:15` `Theme.fontSize / 11`; `haseen.security` `Math.round(12 * Theme.fontSize / 11)` in `Field.qml`, `GroupFilter.qml` and `SelectableText.qml` | `Theme.fontScale` and `Theme.font.body` |
| Omarchy's tokens | `/usr/share/omarchy/shell/Commons/Style.qml:328-339` | caption 10 to iconLarge 18 at base 12 |

Engine probe output from the scenario above:

```
{"body":12,"icon":13,"mono":"BerkeleyMono Nerd Font","cell":12,"cellFamily":"BerkeleyMono Nerd Font","iconCell":13,"helper":6,"squeezed":10,"small":12,"smallFamily":"BerkeleyMono Nerd Font","smallIcon":13,"glyph":13,"glyphFamily":"Symbols Nerd Font","arabic":12,"arabicFamily":"Noto Naskh Arabic","late":12,"metrics":12,"detached":7}
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
