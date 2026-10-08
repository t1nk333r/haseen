# Plan 036: Login — boot splash, greeter, and the password you already typed

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: HIGH (a greeter that does not start is a machine you cannot log into)
- **Depends on**: 003 005 033
- **Category**: desktop
- **Planned at**: 2026-10-05, owner request
- **State**: DONE 2026-10-05 (splash not seen on a real boot; owner step below)

## Problem

haseen's login was tuigreet on VT 1, with no boot splash: a text console, then
a second password prompt on an encrypted machine that had already asked for the
disk password thirty seconds earlier. The owner asked for Omarchy's behaviour —
a splash that owns the screen from the bootloader onwards, and the
authentication at that splash being the login.

## Decision

Three parts, each switchable on its own.

**1. The splash** (`bin/haseen-plymouth-{set,status}`, `share/haseen/lib/plymouth.sh`).
Behaviour from omarchy `bin/omarchy-plymouth-set`: colour the splash from the
active theme, make it the default, rebuild the initramfs. What is **not**
copied is the asset pipeline: Omarchy ships nine PNGs per theme and recolours
them with ImageMagick on every theme change. haseen's theme is a plymouth
*script* that draws what it needs — a breathing accent bar (a scanner since the 2026-10-08 addendum), the password
prompt, the typed bullets — so a theme change substitutes six floats
(`share/haseen/default/plymouth/haseen.script`) and this repository ships no
binary assets. The splash draws the LUKS prompt itself, which is the whole
point: it is the only password an encrypted machine asks for.

**2. The greeter** (`bin/haseen-greeter`, `share/haseen/shell/greeter/`).
Ported from DankMaterialShell's `DMSGreeter.qml` and `Modules/Greetd/`: greetd
runs a bash launcher that starts a throwaway Hyprland whose only job is to run
the greeter shell and exit with it. Authentication is Quickshell's
`Quickshell.Services.Greetd` singleton — the protocol is not reimplemented.
Users come from `getent passwd` filtered to uid 1000–59999 with a login shell;
sessions come from the `.desktop` files in the wayland-sessions and xsessions
directories; the last user and their session are remembered in
`/var/lib/haseen/greeter`.

Two departures from upstream: the login logic is a non-visual
`GreeterSession.qml` so it can be driven with no compositor at all (that is
what makes the handshake testable), and the greeter carries its own
`GreeterPalette`, not `qs.Haseen.Theme` — Theme drags in Config, Paths and the
plugin registry, all of which read a logged-in user's files, and the greeter
runs as `greeter` with none of them.

**3. Autologin** (`haseen setup greeter autologin <user>`). greetd's
`[initial_session]` runs once, at boot, without authenticating; every later
login goes through the greeter. On an encrypted root that is exactly right —
the disk password at the splash authenticated this boot — and the command says
so. On an unencrypted disk it is "anyone who can press the power button is
logged in", so it warns and asks first.

tuigreet stays the default. A greeter that fails to start is a machine with no
desktop, and `sudo haseen setup greeter tuigreet` from a TTY is the way back.

## Verification

- `tests/test-greeter.sh` (44): the generated greetd config for each choice,
  autologin's `[initial_session]` and its refusal of system and unknown users,
  the user filter (uid range, nologin, `/var/empty`), the session parser
  (`Hidden`, missing `Exec`, other groups), argv splitting with field codes and
  quotes, the memory file, the launcher's compositor config, and — against a
  **fake greetd socket speaking the real length-prefixed protocol** — the whole
  handshake: `create_session` for the shown user, the password response, a
  wrong password reported as `Login incorrect`, then `start_session` with
  `["uwsm","start","--","hyprland.desktop"]` and the session remembered.
- `tests/test-plymouth.sh` (28): colours read from the current theme and
  emitted as plymouth floats, the theme files installed, the hook added only
  when missing (HOOKS evaluated the way mkinitcpio evaluates them), `quiet
  splash` added only when absent, the initramfs rebuild and `--no-rebuild`,
  and status on a machine where everything is already in place.
- `tools/smoke-greeter.sh`: the real `shell.qml` under a nested Hyprland with a
  fake greetd. Screenshot shows the card, the user, the focused password field
  and the session line; `greeter state` over IPC lists this machine's three
  sessions. Not a login: nothing authenticated against PAM.

**Not verified, and it needs the owner**: the splash on a real boot and a real
login. Both want root and a reboot:

```
sudo haseen plymouth set && haseen plymouth status   # then reboot
sudo haseen setup greeter haseen                     # then log out
sudo haseen setup greeter autologin $USER            # then reboot
```

If the graphical greeter does not come up, Ctrl+Alt+F2 and
`sudo haseen setup greeter tuigreet && sudo systemctl restart greetd`.

## Amendment 2026-10-06: replacing SDDM

First real target (io, an Omarchy 4 laptop) runs SDDM with autologin. The
desktop layer deliberately keeps an enabled display manager, so there was no
way to get from SDDM to greetd short of hand-run `systemctl`. `haseen setup
greeter tuigreet|haseen` now does it: asks, installs `greetd greetd-tuigreet`,
disables the old unit, enables greetd (enable only), and prints the command
back. The greeter also prefers `hyprland-uwsm`, then `hyprland`, when nothing
is remembered — on a migrated machine the old desktop's session sorts first.
Tests: 53 in `tests/test-greeter.sh`.

Three handover bugs the first real target exposed before its first reboot,
all of which the fake-greetd test passed straight through (it records
`start_session`; it never waits for the greeter to leave):
- `Greetd.launch(…, false)` keeps Quickshell running, and greetd starts the
  session only after the greeter exits: the login would have hung. Now
  `launch(…, true)`, with the remembered-session write made synchronous first.
- `hyprctl dispatch exit` is an error under a Lua config; the dispatcher is
  `hyprctl dispatch 'hl.dsp.exit()'`. Confirmed: `start-hyprland` returns 0
  within 2 s of it.
- greetd runs `haseen-greeter` as `greeter`, whose PATH need not reach
  `/usr/local/bin`: the config now names it by absolute path, and the
  launcher's HOME is always `/var/lib/haseen/greeter` (greetd's user has `/`).
`tools/smoke-greeter.sh` now ends with the real handover: a good password, then
the compositor must exit (`start_session ["uwsm","start","-e","-D","Hyprland",
"hyprland.desktop"]`, compositor gone).

Two more gaps the same machine exposed:
- The greeter's compositor config was hyprlang `.conf`, which Hyprland 0.56
  already flags for removal in 0.57; it is Lua now, and the launcher starts
  Hyprland through `start-hyprland`, without which 0.56 paints a red "started
  without start-hyprland" banner across the login screen. `tools/smoke-greeter.sh`
  now runs the launcher's own generated config.
- haseen never locked before suspend; Omarchy does (its sleep monitor drives
  Omarchy's shell, so it does nothing once that shell is gone). Ported as
  `bin/haseen-lock-before-sleep` + `haseen-sleep-lock.service`, enabled by the
  shell layer: a logind delay inhibitor is held, `haseen shell ipc lock lock`
  runs on PrepareForSleep(true), the inhibitor is released (also when the lock
  does not answer, so a broken shell can never stop a suspend), and retaken
  after resume. Tests: `tests/test-sleeplock.sh` (6), `tests/test-shell.sh`.

## Addendum 2026-10-08: the scanner splash

The owner replaced the breathing bar in `share/haseen/default/plymouth/haseen.script`
with a KITT-style scanner, and the splash now draws no text (owner decision
D11, 2026-10-08):

- A dim accent track, a quarter of the screen wide, with one lit segment (a
  sixth of the track) sweeping back and forth across it, 45 frames each way,
  trailed by four fading ghosts at the positions it passed 3, 6, 9 and 12
  frames earlier. A slow boot still moves, so it still does not look hung.
- Boot messages are no longer drawn: the theme registers no message
  function, and the "Password" label is gone. The LUKS prompt is the
  asterisks alone. While it is up the scanner is hidden; it returns on the
  normal display and hides on quit.
- Still no binary assets: each bar is the accent bullet `•`, stretched.

Verification: `tests/test-plymouth.sh` renders the script and checks that it
still draws the password prompt and registers no message function. Plymouth's
script engine runs only inside `plymouthd`, so the scanner itself is seen only
on a real boot, which stays the owner's check.

### The caret (owner decision, 2026-10-08)

Audit finding F9: before the first key the prompt showed nothing at all. The
owner asked for a small blinking caret where the asterisks appear, still with
no text, inspired by both Knight Rider's KITT and Person of Interest. KITT
gives the colour and the pulse, PoI the surveillance frame and the Machine's
block cursor:

- Four thin corner brackets, 2 px arms 12 px long, in the accent at 0.6
  opacity, frame the field. The field takes the hidden scanner's place: as
  wide as its track and centred on it. It widens only when a long passphrase
  needs the room.
- A block caret (`█`) in the scanner's accent sits where the next asterisk
  goes. The asterisks start at the left padding and the caret follows the
  last one, both in `Monospace 14`. If the initramfs carries no monospace
  font, the label plugin uses its fallback font.
- The caret blinks at 1 Hz: the script plugin refreshes 50 times a second
  (`FRAMES_PER_SECOND`, `src/plugins/splash/script/plugin.c`), so it is lit
  for 25 frames, then fades for 25 along the scanner's ghost falloff, like a
  KITT segment dying away. Each key press restarts the cycle lit.
- On the normal display and on quit the caret, the brackets and the asterisks
  hide. Every colour comes from the splash's colour variables, and no image
  is shipped: the arms are the block glyph stretched.

Verification: `tests/test-plymouth.sh` runs the rendered script under
`tests/fixtures/plymouth-harness.js`, a fake Plymouth in node. It has a
recording Window, Image, Sprite and Plymouth, and Plymouth's local-variable
scoping. The harness drives the refresh, password, normal and quit callbacks
as plymouthd does. 25 assertions cover the following: the caret is lit before
the first key, inside eight bracket arms, in the scanner's colour, with the
scanner hidden; the field is 480 px, centred, on a 1920 px screen; the caret
is lit 25 of every 50 frames and fades out between; after three keys it sits
right after the asterisks and is lit again; 120 keys widen the field; normal
and quit hide all of it. Against the previous script, 39/58 passed, and the
harness itself ran clean on it. After the change, 58/58 passed.

`tools/plymouth-mock.sh OUT.png` draws a labelled mock of that layout with
ImageMagick, before the first key and after three. It uses the haseen theme,
the fontconfig monospace, and rectangles for the block glyph. It is not a
Plymouth render. Whether the real label plugin draws `█` and the font as
expected is seen only on a real boot, which stays the owner's check. The mock
made for this change is `~/.cache/hw/ff-mock/plymouth-luks-prompt-mock.png` on
the author's machine, and it is not committed.

## Execution record

`share/haseen/lib/{greeter,plymouth,boot}.sh`,
`bin/haseen-{greeter,setup-greeter,plymouth-set,plymouth-status}`,
`share/haseen/shell/greeter/`, `share/haseen/default/plymouth/`,
`tools/smoke-greeter.sh`, `tests/test-{greeter,plymouth}.sh`; the caret:
`tests/fixtures/plymouth-harness.js`, `tools/plymouth-mock.sh`.

`lib/boot.sh` is new shared ground, not a new abstraction: the kernel command
line and the initramfs rebuild were already written once inside
`bin/haseen-hibernation-setup`, and the splash needs the same two things.
Hibernation now calls them, so the HOOKS evaluation and the per-bootloader
command line exist once.
