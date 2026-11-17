# Plan 174: the disk-password prompt draws no missing glyphs, centred

## Status

- **Priority**: P1
- **Effort**: XS
- **Risk**: LOW. The splash script and one more image rendered beside the
  logo. Nothing changes how the password is read.
- **Depends on**: 036 (the splash and its prompt), 059 (the mark rendered at
  install), 110 (following the theme)
- **Category**: boot
- **Planned at**: 2026-11-17, from the owner
- **State**: DONE 2026-11-17 (`tests/test-plymouth.sh` 92/92 and
  `tests/test-splash-follow.sh` 285/285; the real plymouthd 26.134.222
  drew the old and new prompt under Xvfb with only its freetype label
  plugin, as the initramfs has it, and the new one centred with six keys
  typed through XTest; IO's next boot is an owner check).

## Problem

The owner, 2026-11-17, with a photo of IO's disk-password prompt: "the
plymouth prompt block indectir broken". The asterisks drew, but the caret
was the font's missing-glyph box, a rectangle with a diagonal stroke, and
the four corner brackets did not show.

The script drew three things from non-ASCII text: the caret was
`Image.Text("█", …)` (U+2588), the brackets were that image stretched, and
the scanner bars were `Image.Text("•", …)` (U+2022) stretched
(`share/haseen/default/plymouth/haseen.script` on origin/main, lines 50 and
116).

The font was not what failed. IO's initramfs carries
`Plymouth-monospace.ttf`, byte-identical to
`/usr/share/fonts/TTF/JetBrainsMonoNerdFont-Regular.ttf` (the sha256 sums of
the file extracted from the UKI's `.initrd` section match). On IO,
`fc-list ':charset=2588'` lists that font, so it has the block.

The decoding failed. The mkinitcpio hook copies only
`label-freetype.so` into the initramfs (`/usr/lib/initcpio/install/plymouth`
on IO, the `add_binary` list). Its `load_glyph` decodes each character with
`mbrtowc` (`src/plugins/controls/label-freetype/plugin.c` on Plymouth's main
branch, 2026-11-17, lines 293-298). plymouthd runs in the C locale in the initramfs,
so `mbrtowc` returns `(size_t)-1` for a multibyte character. The check
`character_size <= 0` does not catch that, because `size_t` is unsigned. The
character is then left unset and freetype loads glyph 0, the missing-glyph
box. ASCII is one byte and decodes in any locale, which is why the asterisks
drew.

The fault reproduces on luna with the real plymouthd 26.134.222 and its x11
renderer. Xvfb served a 1920x1080 screen. plymouthd ran in a user, mount
and network namespace, with the theme bind-mounted over
`/usr/share/plymouth/themes`, `LC_ALL=C`, and `label-pango.so` hidden
behind `/dev/null` so that only the freetype plugin loads. In that run the
old script drew a hatched box for the caret, 1 px dotted stubs for the
brackets and a smeared scanner. With the pango plugin present, which decodes
UTF-8 itself, the old script drew correctly. That explains why a desktop
test never showed the fault.

A follow-up from the owner the same day: "center the password prompt as
well make it calculate the absiliote center". The field was centred, but
inside it the asterisks started at the left padding, so the typed line sat
left of the screen's middle (the photo). The field's vertical centre was
also `bar_y + bar_height / 2`, 2 px below the screen's centre.

## Decision

- Every string the script draws is ASCII. Solid shapes come from
  `block.png`, an 8 px square in the accent colour that `haseen plymouth
  set` and `haseen plymouth apply` render with ImageMagick next to
  `logo.png` (`plymouth_install_block` in `share/haseen/lib/plymouth.sh`).
  The script stretches it into the scanner's track and segments, the caret
  and the bracket arms. The caret is one asterisk's cell
  (`Image.Text("*", …)`'s width and height), so it lines up with the text.
- Without magick, the script falls back to an ASCII underscore in place of
  the block. The splash then looks plainer, but nothing draws as a missing
  glyph, and the install warns.
- The prompt is centred on the screen's exact centre, computed once in
  whole pixels (`centre_x`, `centre_y`, with Plymouth's `Math.Int`). The
  asterisks and the caret are laid out as one line centred on that point,
  so the line grows both ways as keys are typed. The brackets are centred
  on it and widen past the scanner's track for a long passphrase. The
  scanner's track is centred on the same point, and the mark keeps its
  place 72 px above it.
- The repository still ships no binary asset: the block is rendered at
  install time, like the mark.

## Rejected

- **Naming a font with the glyphs.** The font already has them, so a font
  change would not help (above).
- **Setting a UTF-8 locale for plymouthd in the initramfs.** That needs
  locale data and an environment in the initramfs that haseen does not own.
  The mkinitcpio hook and the systemd units are Plymouth's.
- **Shipping block.png.** The repository has no binary assets (plan 059),
  and the colour has to follow the theme.

## Verification

- `tests/test-plymouth.sh`: the rendered script is ASCII only. Under the
  fake Plymouth (`tests/fixtures/plymouth-harness.js`, which now returns an
  8 px `block.png`), the caret is `block.png` at one 11x22 cell and the
  brackets and scanner are the block. Every string passed to `Image.Text`
  is printable ASCII. Without `block.png` (`HARNESS_NO_BLOCK=1`), the caret
  is a stretched underscore that still shows before the first key. Before
  a key, with three keys and with 120, the line's two side gaps differ by
  at most one pixel around x 960 and the caret's middle is on y 540 of the
  1920x1080 screen; the field is `[720,517,1200,563]` and the scanner's
  track is centred on (960, 540). The
  existing layout and blink checks still pass.
- The real-plymouthd render above, repeated with the new script: a solid
  caret, solid corner brackets and a crisp scanner.
