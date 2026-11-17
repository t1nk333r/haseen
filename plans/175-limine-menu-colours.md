# Plan 175: Limine's menu in the theme's colours

## Status

- **Priority**: P2
- **Effort**: S
- **Risk**: MEDIUM. It edits the ESP's `limine.conf`, which haseen
  otherwise edits only for the menu wait (plan 104). The edit uses the same
  rules: only known header lines, a backup, Limine's lock, re-enrolment or
  the way back.
- **Depends on**: 104 (the menu wait and its root helper), 110 (the splash
  follows the theme), 174
- **Category**: boot
- **Planned at**: 2026-11-17, from the owner
- **State**: DONE 2026-11-17 (`tests/test-omarchy45-boot.sh` 281/281,
  `tests/test-splash-follow.sh` 285/285; IO's menu is recoloured with
  `haseen setup boot-menu colours`, and the menu's look at the next boot is
  an owner check).

## Problem

The owner, 2026-11-17: "make the bootloader get my colors i am on IO". IO
boots through Limine 12.9.4. Its `/boot/limine.conf` header still carries
the Tokyo Night colours that Omarchy's installer wrote:
`term_background: 1a1b26`, `interface_branding_color: 9ece6a`, a Tokyo
Night `term_palette`, and so on. IO's haseen theme is a dark grey with an
orange accent (`#171717`, `#CCD0CF`, `#F25623`), and the boot splash after
the menu already uses those colours (`/var/lib/haseen/splash` on IO reads
`171717-ccd0cf-f25623-kufic`). Nothing in haseen sets Limine's colours, and
limine-entry-tool has no key for them, so the header has to be edited the
way plan 104 edits the wait.

From Limine's documentation (`/usr/share/doc/limine/CONFIG.md` on IO,
lines 190-253) and its menu code (`common/menu.c` on the limine trunk), the
menu draws:

- the entries in `term_foreground` on `term_background`, and the selected
  entry in reverse video (`\e[7m`, menu.c:1430);
- the entries' comments in the palette's cyan (`\e[36m`, menu.c:1670);
- the branding in `interface_branding_colour`, the key help in
  `interface_help_colour` and the countdown digit in
  `interface_help_colour_bright`;
- `backdrop` around a centred wallpaper.

`interface_*_color` is an alias that Limine reads when the `_colour`
spelling is absent (menu.c:1836-1853). Omarchy's file uses the alias.

## Decision

- `haseen setup boot-menu colours` gives the menu the splash's three
  colours: the current theme's background, text and accent. The text and
  accent are drawn readable as on the splash (`plymouth_readable`), so the
  screen does not change palette between Limine and the disk password. The
  mapping, `bootmenu_colour_spec` in `share/haseen/lib/bootmenu.sh`:
  - `term_background` and `backdrop`: the background;
  - `term_foreground` and `term_foreground_bright`: the text;
  - `interface_branding_colour` and `interface_help_colour`: the accent,
    and `interface_help_colour_bright`: the text;
  - `term_palette`: the background, five times the accent (the editor's
    syntax colours), then a muted cyan (the text 60% of the way from the
    background, for the comments) and the text;
  - `term_palette_bright`: the same with a grey (35%) first;
  - `term_background_bright`: the background 15% towards the text.
- Each option keeps its existing header line and spelling. A missing option
  is added just above the first entry, and nothing else changes. A header
  that sets one option twice (in either spelling) is refused, as is a file
  without entries. Options inside an entry are left alone.
- The command takes the same steps as `fast`: the check that no config
  shadows the ESP's, the enrolment plan, confirmation, a backup in
  `/var/lib/haseen/boot-menu/`, the root helper (`limine-header.sh
  colours`) under Limine's boot-partition lock, then re-enrolment, or the
  backup restored. The first run records the values it replaced in
  `/var/lib/haseen/boot-menu/colours`. `colours-off` puts them back
  (`limine-header.sh uncolour`, which accepts only known options with hex
  values) and deletes the record. `colors` and `colors-off` are accepted as
  the same verbs.
- Following. Root reads no one's theme, so a run that reruns itself as root
  passes the colours as `colours BG-FG-ACCENT`. While the record exists,
  `haseen plymouth apply`, the root side of the splash following the theme
  (plan 110), recolours the menu with the same request's colours. It runs
  after the rebuild and its record, keeps one rolling backup
  (`limine.conf.followed`), and only warns when it cannot. Following never
  runs where a config hash is enrolled (`plymouth_signed_boot`), so there
  is nothing to enrol again there. Elsewhere, by hand, `colours` re-enrols
  as `fast` does.
- Opt-in, like the menu wait: no layer or migration runs it.

## Rejected

- **Carrying the theme's sixteen ANSI colours to Limine.** The follow
  request, the root side's only input, carries three colours (plan 110), and
  widening it means widening that parser and its polkit-reachable surface.
  Three colours also make the menu and the splash one screen. With 16
  colours, the comments would come out in whatever cyan a theme picked.
- **Making `haseen plymouth set` recolour Limine as well.** It is the
  by-hand path that also runs on signed machines, where an edit has to be
  enrolled again. `haseen setup boot-menu colours` already does that, and
  `set`'s own rebuild leaves the menu as it was.
- **Following without opting in.** It edits a file on the ESP that haseen
  did not seed, so the owner's first `colours` run is the consent, as `fast`
  is for the wait.
- **Rewriting the whole header from a template.** That would drop
  `interface_branding`, `default_entry`, `hash_mismatch_panic` and the
  owner's own lines. Only the colour lines are haseen's to change.

## Verification

- `tests/test-omarchy45-boot.sh`:
  - the spec from three colours;
  - Omarchy's header recoloured in place with its `_color` spelling (ten
    lines changed, none added), and the snapshot putting it back;
  - a bare header given the options above the entry, and `-` removing them
    again;
  - an option inside an entry left alone;
  - refusals for a duplicate across spellings, no entry, and record lines
    that are not hex colours of known options;
  - the helper for real: colours, uncolour, a bad colour and a bad record,
    with the file left alone on both;
  - the command, dry: the theme's colours drawn readable, the backup before
    the record before the helper, `colors` as an alias, refusal without a
    theme and of a malformed rerun, "already wears" when nothing changes,
    `colours-off` with and without a record or with a bad one, status in
    both states, and the root step when the ESP is root-only.
- `tests/test-splash-follow.sh`: with no record, `apply` leaves Limine
  alone. With one, it recolours after the stamp in the readable colours,
  after a rolling backup. A layout it cannot recolour warns, edits nothing
  and does not fail the splash.

## Review

DeepSeek Flash reviewed the first head (round 1, REQUEST_CHANGES, no
blockers). Two should-fix findings were taken:

- `colours` returned "already wears" whenever the menu matched, even with no
  record. After a wiped `/var/lib/haseen` the menu then never followed the
  theme. The shortcut now needs the record. Without it the edit runs,
  changes no byte, and writes the record.
- The record kept raw header values that Limine reads but `uncolour`
  refuses (`0x1a1b26`, a palette with a space after `;`, `#1a1b26`, an empty
  value), so `colours-off` could be locked out for good.
  `bootmenu_colour_problems` now refuses such a file before anything
  changes, and the `colours-off` error names the record.

The status line no longer says the colours follow the splash. It says they
follow where the splash does and points at `haseen plymouth follow status`.

Rejected from that round:

- Writing `term_background` as `ff` plus the colour. Limine documents TT as
  transparency, so the six-digit form, TT 00, is opaque.
- Clearing a stale `block.png` without magick, so it matches `logo.png`.
- Moving the record write after the edit. A kill after the edit would then
  lose the original values, which is worse than a record of an edit that
  never happened.

