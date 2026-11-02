# Plan 153: Wooting profile settings, read only

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: LOW. wootingd sends no new command to the keyboard: it decodes
  two replies it already asked for. Each profile object in its JSON gains
  six fields, and clients that do not read them are unaffected
  (`haseen wooting list` keeps its three columns). Nothing is written to
  the keyboard.
- **Depends on**: 099 (haseen.wooting and wootingd), 109 (interface
  language)
- **Category**: daemon, shell, plugins
- **Planned at**: 2026-11-02, owner decision (below)
- **State**: DONE 2026-11-02 (`tests/test-wooting.sh` 292/292,
  `tests/test-wootingd.sh` 25/25 with the daemon's 57 cargo tests; read on
  the owner's 60HE+ below)

## Decision (owner, 2026-11-02)

The owner sent "Wootingd
https://github.com/OpenKeyboard-Pr0ject/openkeyboard/tree/main". Asked what
wootingd should take from it, the owner chose **"Read-only first"**: check
the facts on the 60HE+ with read-only commands, then show each profile's
actuation, Rapid Trigger, Tachyon Mode and colour in the status output and
the panel, with no writes to the keyboard.

- Rejected, **"Read and edit"**: also change actuation and Rapid Trigger
  from haseen. OpenKeyboard's notes say a profile write goes straight to
  flash with no commit step (`docs/wooting.md:391`), and that sending a
  long write in the wrong report size stored damaged lighting on their
  keyboard (`docs/wooting.md:35`, `:313`).
- Rejected, **"Plan only"**: record the gap and stop.

Not offered, because neither can work:
- vendoring OpenKeyboard: it is a React and TypeScript browser app on WebHID
  (its `README.md`, `package.json`), AGPL-3.0, with no daemon, CLI or socket;
- replacing wootingd with it, for the same reason. haseen's shell has no HID
  access (plan 099), so something must own the keyboard and speak a socket.

## Source

OpenKeyboard, `github.com/OpenKeyboard-Pr0ject/openkeyboard`, commit
`4029a069189e5542e86ebceaac9d95e8b95e885e` (main on 2026-11-02), AGPL-3.0.
Its 33 commits are all by one third-party author, 2026-10-12 to 2026-10-16
(`git log`). It was verified on a Wooting 80HE TenZ, firmware 2.14.0 and
2.14.1, on Windows (`docs/wooting.md:3`).

AGPL-3.0 is not MIT, so it is a source of facts only, like wootswitch in
plan 099. wootingd states field numbers and encoding ranges and cites
`docs/wooting.md` by line. No code or text is copied or quoted, and the
test vectors are captures from the owner's keyboard or bytes written for
the tests, not OpenKeyboard's captures. `NOTICE.md` lists it under factual
inputs. `plans/.known-external-refs` records the pin.

Facts taken (`docs/wooting.md`):
- the profile-settings reply (command 0x27) is a protobuf whose field 1 is a
  message: field 1 actuation point, 3 Rapid Trigger on or off, 4 its
  sensitivity, 7 continuous Rapid Trigger, stored inverted, and Tachyon Mode
  in fields 5 and 9 together (`:133-144`);
- the metadata reply (0x37) has a colour message in field 2, with red, green
  and blue in its fields 1, 2 and 3 (`:115-121`);
- a distance is precise, 0x4000..=0x7FFF over 0x3FFF steps, or legacy,
  0..=0xFF over 255, both spanning 0 to 4 mm (`:166-167`); Wootility
  sets actuation from 0.1 to 4.0 mm and Rapid Trigger sensitivity from 0.1
  to 2.35 mm, in 0.05 mm steps (`:158`).

Known there and not taken: per-key actuation (0x31) and per-key Rapid
Trigger (0x3D), lighting (0x32, 0x23, 0x24, the live frame 0x4A), and every
write.

## The probe

A script outside the repository sent only commands wootingd already sends
(`core/wootingd/src/proto.rs`: 1, 11, 39 = 0x27, 55 = 0x37), from an
allowlist, to the 60HE+'s config interface (hidraw7, usage page 0xFF55),
while the old daemon ran. It wrote nothing. Firmware read 2.14.1; the active
slot was 0.

| Slot | 0x37 metadata | 0x27 settings | Decoded |
|---|---|---|---|
| 0 | `1 Typing Profile`, icon, no colour; report 2, 32 bytes | `0a 14 08 ff cf 01 10 01 18 00 20 90 a0 01 28 00 30 02 38 01 48 00` | actuation 0x67FF = 2.50 mm, Rapid Trigger off, sensitivity 0x5010 = 1.00 mm, continuous off, Tachyon 0 |
| 1 | `Monkeytype`, icon, no colour; report 1, 26 bytes | `0a 14 08 80 a0 01 10 01 18 00 20 e6 8c 01 28 00 30 02 38 01 48 00` | 0x5000 = 1.00 mm, off, 0x4666 = 0.40 mm, continuous off, Tachyon 0 |
| 2 | `Firefly`, colour message `08 ff 01 10 d4 01 18 5c` = (255, 212, 92), icon; report 2, 33 bytes | `0a 14 08 99 b3 01 10 01 18 00 20 e6 8c 01 28 00 30 02 38 01 48 00` | 0x5999 = 1.60 mm, off, 0.40 mm, continuous off, Tachyon 0 |
| 3 | empty | empty | no profile |

Two findings beyond OpenKeyboard's notes:
- **This keyboard matches the 80HE's layout.** All three settings payloads
  have the fields in the same order and encoding as OpenKeyboard's 80HE
  captures. Every distance here is precise.
- **Long replies come in report 2.** proto.rs said every reply arrived as
  one 33-byte report (plan 099, firmware 2.14.0). On 2.14.1 a metadata
  payload over 26 bytes arrives as input report 2, 63 bytes, which
  wootingd's 128-byte buffer (`MAX_REPLY`) already holds whole. Comments
  now say so (`proto.rs:191`, `:309`).

## What changed

### wootingd

- `proto.rs`:
  - `read_varint` and `protobuf_varint` (`:417`, `:436`): varint fields with
    multi-byte keys and lengths. A value cut short, or one with bits past the
    64th, is None, never a guess.
  - `travel_hundredths` (`:475`): both encodings, in hundredths of a
    millimetre, rounded to the 0.05 mm step in integers. Raw values between
    the two ranges, or above them, are not distances, and neither is zero:
    Wootility sets nothing below 0.1 mm, so a zero is more likely unset.
  - `ProfileSettings::decode` (`:496`, `:512`). Every value is an `Option`:
    a payload that does not carry a field shows nothing rather than a wrong
    value. Either Tachyon field set means on, because which one the firmware
    reads is not known (`docs/wooting.md:144`).
  - `ProfileMeta::decode` (`:543`, `:552`): the name as before, and the
    colour only when its message arrived whole.
  - 6 tests, built from the captures above.
- `device.rs`: `profile_settings` (`:410`) replaces `profile_stored`. It is
  the same 0x27 read, and an empty reply still means the slot holds no
  profile. `profile_meta` (`:425`) replaces `profile_name`, again the same
  0x37 read.
- `main.rs`:
  - each profile object gains `actuation` and `sensitivity` (millimetres
    with two decimals, as Wootility shows them: `2.50`), `rapidTrigger`,
    `continuous` and `tachyon` (true or false), and `color` (`"#rrggbb"`).
    Each is null when the keyboard did not say (`json_mm` at `:181`). The
    active slot kept without stored data has all six null (`Profile::bare`,
    `:72`).
  - `identify` reads nothing new (`:335-338`).
  - `doctor` prints one line per stored slot (`:911`, `settings_summary` at
    `:200`).
  - 2 tests pin the JSON and the doctor wording.

### Clients

- `bin/haseen-wooting status` prints the settings indented under each
  profile, for example `actuation 1.00 mm, continuous Rapid Trigger 0.40 mm`.
  One jq definition builds the line (`SETTINGS_JQ`, `:121`). A tab is
  whitespace to `read`, so an empty field merges into the next one. The
  settings are therefore the last field, where an empty one shifts nothing,
  and the name before them is never empty, since wootingd labels an unnamed
  slot (`:170`). `list` keeps its documented three
  columns, and `list --json` passes the new fields through.
- `Model.js`:
  - `profileEntry` (`:91`) keeps the six values, and turns anything that is
    not a value of its kind into null. Travel must be a finite number from 0
    to 4 mm; the colour must be `#rrggbb`.
  - `settingsParts` (`:119`) gives the phrases, each English with `%1` for
    the millimetres and marked for `tools/i18n.py`. Continuous qualifies
    Rapid Trigger only while Rapid Trigger is on, because the firmware keeps
    the flag either way.
  - 15 checks.
- `ProfileRow.qml` draws a second, smaller line in `Theme.subtle` of
  whatever is under it, and a dot in the profile's own colour, ringed with
  `Theme.border`, on the right. Each appears only when the keyboard reported
  it. The colour is the keyboard's data, not a theme colour; the plugin
  still has no colour literal (`tests/test-wooting.sh`).
- `Panel.qml:111-112` joins the translated phrases with ` · ` and formats
  the millimetres in the language's digits (`I18n.formatNumber`).
- Six new interface strings in `share/haseen/i18n/en/shell.json`, with
  Arabic in `ar/shell.json` (machine translation, per its provenance;
  Rapid Trigger, Tachyon and `mm` stay Latin, as the provenance note keeps
  product names and unit abbreviations).
- `tools/fake-wootingd.py`: slot 0 carries the 60HE+'s slot 0 settings. Slots
  1 to 3 carry made-up values that cover continuous Rapid Trigger, Tachyon
  Mode, a colour, and a profile the daemon could not decode. Millimetres are
  written with two decimals, as the daemon writes them.

### Why a new line in the panel

AGENTS.md asks for a reason for any new on-screen element. The owner asked
for these values in the panel (decision above). They appear only inside the
profile panel, which opens on demand, and the bar is unchanged.

## Evidence

- On the owner's 60HE+ (firmware 2.14.1), with the binary built from this
  branch, while the old daemon ran (read-only, two processes on one hidraw
  node, as the probe was):
  - `wootingd doctor` printed `slot 0        : actuation 2.50 mm, Rapid
    Trigger off, Tachyon Mode off`, `slot 1 … 1.00 mm …` and
    `slot 2 … 1.60 mm …`;
  - the daemon on a private socket answered `status` with
    `{"slot":2,"name":"Firefly",…,"actuation":1.60,"rapidTrigger":false,
    "sensitivity":0.40,"continuous":false,"tachyon":false,
    "color":"#ffd45c"}` and its log line read `3 of 4 addressable slots hold
    a profile, active 0`.
- `cargo test --locked`: 57 passed (49 before).
- `node share/haseen/shell/plugins/haseen.wooting/tests/model.test.js`: 284
  passed (269 before).
- `tests/run.sh tests/test-wooting.sh`: 292/292, including the real engine:
  the panel's rows read `Actuation 1.60 mm · Rapid Trigger off · Tachyon
  Mode|#ffd45c` for the fake's slot 2, and nothing for the undecoded slot 3.
- `tests/run.sh tests/test-wootingd.sh`: 25/25.
- `tools/i18n.py check`: catalogs fresh and complete for en and ar.
- `tests/run.sh --affected`: 20 of 172 files (the catalogs widen it),
  2620/2621. The one failure was `tests/test-shell.sh`'s ban on colour
  literals in the plugin tree, which a model test's `"#FFD45C"` broke. The
  test now builds the string. Rerun after the fix, `tests/test-shell.sh` with
  `tests/test-wooting.sh`: 575/575.

## Review

DeepSeek Flash reviewed PR 113 at `671e2adbdb27453ee4616d11893679cfdea0b65e`
and approved it with no blocker and no should-fix. It reran cargo (57),
`tests/test-wooting.sh` (292/292), `tests/test-wootingd.sh` (25/25), and
the affected selection (20 files, 2621/2621). It also fed 89,905 payloads
through both decoders: none panicked, and every travel stayed within
0..=400. Its diff audit found no new command and no write in `device.rs` or
`main.rs`. It did not rerun the hardware reads or compare every upstream file
for the licence, and it said so. Its nits and what became of them:

1. A raw 0 decoded to `0.00 mm`. Fixed: zero is unset (`travel_hundredths`
   above), because Wootility sets nothing below 0.1 mm.
2. A malformed colour message, whole but unparsable, read its missing
   components as 0. Kept: the outer length is checked first, so this needs
   firmware that sends a broken message; protobuf leaves zero components
   out, so an absent one must read 0.
3. The status comment's reason was weaker than stated: a tab is whitespace
   to `read`, so an empty name would shift the fields after it. Fixed: the
   comment and this plan now give the real reason, and wootingd never sends
   an empty name.
4. A tenth varint byte above 1 lost its high bits silently. Fixed:
   `read_varint` returns None, and a test pins `u64::MAX` and the 65th bit.
5. `status` names Tachyon Mode only when it is on, while `wootingd doctor`
   prints on or off. Kept: the panel and `status` list what is on, and
   `doctor` is a diagnostic.

Rechecking every OpenKeyboard citation against the pinned file for this
round found three in this plan that pointed at blank or wrong lines (they
now read `:391`, `:313` and `:158`) and one, `:116-121`, that started a
line early (now `:115-121`, here and in `proto.rs`).

A delta round on `b1439db74885cf3793b822476dfa2c4138110661` approved the
fixes. It fed all 65,536 raw travel values and all 256 tenth varint bytes
through the decoders, and reran cargo (57) and both suites (317/317). Its
nits were wording: a comment line that had swallowed a paragraph break, the
count of wrong citations (three, not four), the reason zero is unset but
0.05 mm is not, and a model test still labelled as if wootingd sent 0 mm.
All four are fixed. Two notes need no change: a profile name with a tab in
it would still shift the status columns, as before this plan, and this
section now records more of round 1's evidence.

## Residual unknowns

- **Tachyon Mode and Rapid Trigger on, on this keyboard.** All three profiles
  read Rapid Trigger off and both Tachyon fields 0. That a 1 there means on
  rests on OpenKeyboard's 80HE. To check: turn Tachyon Mode or Rapid Trigger
  on for one profile in Wootility, then run `haseen wooting status` within
  30 s, which is the daemon's re-read interval (`main.rs:274`).
- **Per-key values.** A key with its own actuation or Rapid Trigger
  overrides the profile values shown here. Reading those (0x31, 0x3D) would
  be two commands wootingd has never sent. OpenKeyboard used both read-only
  on the 80HE. That is a next step if wanted, not part of this plan.
- **luna's daemon.** luna's `wootingd.service` still runs the old plugin's
  build (`systemctl --user show wootingd -p ExecStart`: the
  `t1nk33r.wooting` tree under `~/.config/omarchy/plugins/`). That build
  sends none of the new fields, so the panel there shows no settings line
  until `haseen setup wooting on` points the unit at haseen's daemon (an
  owner step; plan 099).
