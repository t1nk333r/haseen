# Plan 099: Adopt t1nk33r.wooting as haseen.wooting, with its Rust daemon

## Status

- **Priority**: P2
- **Effort**: L
- **Risk**: MEDIUM (a second compiled language in the build and CI; a setup step that writes a root udev rule and a user unit and takes over the owner's plugin's copies of both; a migration that rewrites one `shell.json` id; nothing changes for a HOME that does not use the plugin)
- **Depends on**: 005 011 028 032 074 095 096 097 098
- **Category**: shell, plugins, build
- **Planned at**: 2026-10-21, owner decision (below)
- **State**: DONE 2026-10-21 (`tests/test-wooting.sh` 286/286, `tests/test-wootingd.sh` 25/25 with the daemon's 49 cargo tests; affected suites and gates in Evidence)

## Decision (owner, 2026-10-21)

Recorded as given:

- "adopt t1nk33r.wooting": port it as the first-party plugin
  `haseen.wooting`, like plans 095–098.
- Asked how to take in its Rust daemon wootingd, the owner chose **"Vendor
  the Rust"**: copy wootingd unchanged into haseen and build it with cargo
  next to haseen-sidecar (`tools/build-sidecar.sh`). CI gains the `rust`
  package and runs its 49 Rust tests.
  - Rejected, **"Port it to Go"**: one toolchain, but about 2,800 lines
    rewritten and the HID path unprovable without a keyboard.
  - Rejected, **"Keep it external"**: `haseen setup wooting` building from
    the haseen-wooting repo; the daemon stays outside haseen.
- Asked whether it is on by default, the owner chose **"Off by default"**.
  A migration renames `t1nk33r.wooting` to `haseen.wooting` where it is
  already enabled.

AGENTS.md's adopted list gains the line "plan 099, the owner's plugin (owner,
2026-10-21): haseen.wooting, with its vendored Rust daemon wootingd."

## Source

`t1nk333r/haseen-wooting` (the owner's, private, MIT, Copyright (c) 2026
t1nk33r), commit `184f6fabf7f9b54c9bd48870cfd64596f086cfc7`, the tree installed
on luna as `~/.config/omarchy/plugins/t1nk33r.wooting` (read only; nothing
there was written). Files were copied, never its history, and not its agent
and planning notes (`CLAUDE.md`, `HANDOFF.md`, `PROJECT_MAP.md`,
`ROADMAP.md`), its CI file or `daemon/target/`. Every copied file was scanned
before commit for locations, host addresses, tailnet ranges, home paths,
tokens and serial numbers: the only serial-shaped value is the fake daemon's
placeholder `A00B0000W00T00000S00H00000`.

## What was built

### haseen.wooting (bar widget + panel)

`share/haseen/shell/plugins/haseen.wooting/`, `"kinds": ["bar-widget",
"panel"]`, in no default bar section or service
(`share/haseen/default/shell.json`). Settings keep the original's names and
defaults: `showName` true, `hideWhenAbsent` true, `nameMaxChars` 12.

- `Widget.qml` (from the original `Panel.qml`): a `BarButton` with the
  keyboard glyph and `Model.shortName` of the active profile; it takes no
  room while no keyboard is attached; a click opens the panel.
- `Panel.qml` (the original's popup card and its full-screen
  `LayoutPanel.qml`, in the one lazy panel haseen gives a plugin): the stored
  profiles, a click switches through the daemon and closes the panel, the
  daemon's refusals shown in the urgent colour, and a Keyboard layout pill
  that loads `Board.qml`.
- `Board.qml` (from `LayoutPanel.qml`): the board drawn from the firmware's
  row/column matrix, key travel and actuation live, the Fn layer the daemon
  learned, unmapped keys listed. Its socket subscribes to the analog stream
  only while it exists.
- `WootingLink.qml`: the socket lifecycle both original QML files repeated,
  once: a `FileView` watch on the socket path (inotify, no poll), one fresh
  `Socket` per attempt, `Model.linkStep` deciding, one marked
  `// haseen:ui-timeout` 2 s retry at most three times while the socket file
  exists.
- `Model.js` and `tests/model.test.js`: the original's, logic unchanged
  (269 checks under node); comments name haseen's places and pin the SDK
  citations.
- `ProfileRow.qml`: written for the port (the original used Omarchy's
  `qs.Ui` Button).
- Colours are `Theme` tokens only: the layout view's `Qt.rgba(1, 1, 1, …)`
  fills became `Theme.surfaceAlt`/`Theme.surface`, the travel fill
  `Qt.alpha(Theme.accent, 0.15 + 0.85 × travel)`; `tests/test-wooting.sh`
  asserts no colour literal and no compat import.

One behaviour fix found by the engine test: a JS object handed through a QML
signal's `var` parameter comes back with arrays that are not `Array`s, so
`Model.applyMessage` dropped every profile. `WootingLink` emits the daemon's
line and each consumer parses it (the original parsed in place and never
crossed a signal).

Dropped: the popup's Settings row (`omarchy-menu toggle setup.plugin`), the
overlay's scrim and own Escape handling (haseen's panel host closes on Escape
and outside clicks), the `omarchy` manifest block.

### wootingd, vendored

`core/wootingd/` holds the crate as it was: `Cargo.toml` and `Cargo.lock`
byte-identical (`diff` of both), one dependency `parking_lot`, and `LICENSE`.
`diff` of each source file with comment lines removed shows these changes,
and no other:
- three messages:
  - the permission hint names `haseen setup wooting on` instead of
    `./install.sh`;
  - the no-echo error reads "none of 8 reads echoed it";
  - the empty active-profile error reads "active profile (command 11): empty
    payload".

  The old wordings of the last two followed the unlicensed wootswitch
  (below).
- four command constants renamed, with their uses (below).

Comments gained a provenance header per file and the citation changes
below.

`tools/build-sidecar.sh` builds it after the Go helpers with `cargo build
--release --locked --quiet` and `CARGO_TARGET_DIR` outside the tree
(`$XDG_CACHE_HOME/haseen/wootingd-target` unless set), and installs the
binary as `share/haseen/sidecar/wootingd` (ignored in `.gitignore`).
Without cargo it prints "no cargo; wootingd not built, so haseen.wooting and
'haseen setup wooting' cannot work (pacman -S rust …)" and continues, as the
Go part does without go; likewise for a cargo that does not run (rustup's
proxy with no toolchain, which is how this laptop's sandboxed tests first
failed) and for a failed build, because the daemon serves one off-by-default
plugin and must not stop `install.sh`. `HASEEN_REQUIRE_CARGO=1` turns each
into exit 1. `HASEEN_BUILD_SIDECAR=0` / `HASEEN_BUILD_WOOTINGD=0` leave one
part out, so `tests/test-sidecar.sh` and `tests/test-wallpaper.sh` build only
Go; `tests/test-omarchy-commands.sh`'s real tree install stubs `cargo` as it
already stubbed `go`, keeping the build out of the checkout.
CI's `ARCH_PACKAGES` gains `rust`. `docs/architecture.md` §5.7 records the
second compiled language.

### Commands

- `bin/haseen-wooting` (from `bin/wooting`): `status`, `get`, `list`,
  `set SLOT|NAME`, `analog [--json|--follow]`, `fn`, `doctor`; same output,
  same exit-code registry (0, 1, 2, 3 daemon not reachable, 4 no keyboard,
  5 dependency missing). `set --dry-run` resolves the slot and prints
  `DRYRUN: wootingd profile set N` without sending it.
- `bin/haseen-wooting-doctor` (from `bin/wooting-doctor`): the same checks
  and order; defaults read through `sysroot_path`; hints name haseen's
  fixes; one more advisory check, which `wootingd.service` the user manager
  runs (haseen's, the plugin's, someone else's, none).
- `share/haseen/lib/wooting.sh` (from `lib/ipc.sh`): `wooting_socket`,
  `wooting_send`, and the ownership helpers below.

### `haseen setup wooting [on|off|status] [--dry-run] [--yes]`

From the original `install.sh`/`uninstall.sh`, on `common.sh`'s helpers only
(`install_root_file`, `run_root`, `replace_user_file`, `write_user_file`,
`run`); no new `sudo ` line (`grep -rn 'sudo ' bin share | grep -v common.sh`
counts 100 lines before and after). System state is read through
`sysroot_path`; live probes (`systemctl --user is-active`, `pgrep`) are
skipped in a sysroot.

- `on`: installs `share/haseen/default/udev/70-wootingd.rules` as
  `/etc/udev/rules.d/70-wootingd.rules`, reloads udev, writes
  `~/.config/systemd/user/wootingd.service` from
  `share/haseen/default/systemd/wootingd.service` with
  `ExecStart="PREFIX/share/haseen/sidecar/wootingd"` (quoted as the original
  did), reloads the user manager, and with a Wooting attached re-runs the
  rules on it (`udevadm trigger --action=change --parent-match=…`) and
  restarts the unit. Nothing enables the unit: the rule's `TAG+="systemd"`,
  `SYSTEMD_USER_WANTS` and the unit's `BindsTo=` keep the daemon device-gated
  as before. A real run refuses while the daemon is not built.
- `off`: stops and removes haseen's unit, removes haseen's rule and reloads
  udev; a copy that is not haseen's is reported and left.
- Idempotent: `on` with both files current does nothing; `off` twice is
  "already off".

#### One owner: the coexistence design

The plugin's `install.sh` installs `/etc/udev/rules.d/70-wootingd.rules` and
`~/.config/systemd/user/wootingd.service` (running
`…/t1nk33r.wooting/daemon/target/release/wootingd`); luna has the unit
today. Chosen: **the same names and a take-over.**

- One rule file name, so one rule; it can want only `wootingd.service`; that
  name resolves to one unit file, and `~/.config/systemd/user` outranks every
  system unit directory. Whatever happens, the keyboard starts one daemon.
- `on` recognises the plugin's copies (its rule's header line "Wooting
  Profiles plugin (t1nk33r.wooting)", which its `uninstall.sh` also keys on;
  its unit's `Documentation=` line), saves them to
  `~/.local/state/haseen/wooting/replaced-<time>/`, replaces them, removes an
  older install's `default.target.wants/wootingd.service` link (which would
  otherwise start haseen's daemon at every login), and `restart`s the one
  unit, so a daemon of the old unit stops before haseen's starts.
- A file of either name that is neither haseen's (its first line
  `# haseen: setup wooting (plan 099)`) nor the plugin's is refused, not
  replaced, even under `--yes`.
- wootingd itself refuses to start beside a live socket
  (`core/wootingd/src/main.rs`, "another wootingd is already listening"), and
  `on` warns about a wootingd running outside systemd.
- The plugin's directory is never read or written. `off` does not restore
  the saved copies; the plugin's own `install.sh` reinstalls them. After
  removing haseen's copies, `off` names each saved directory
  (`~/.local/state/haseen/wooting/replaced-<time>/`) with the files in it,
  and that installer, `~/.config/omarchy/plugins/t1nk33r.wooting/install.sh`
  (review round 1).

Rejected: **detection and a refusal** (different names, `on` refusing while
the plugin's files exist). It leaves two rules able to want two units, so a
later plugin install brings back two daemons racing for the interface (the
socket guard's check-then-unlink has a window between bind and listen), and
it asks the owner to run the plugin's `uninstall.sh` first, which the brief
forbids haseen to do itself.

### Migration

`share/haseen/migrations/1792577102-adopt-wooting.sh`, after
`1792531693-omarchy-path.sh`, shaped on `1791560100-adopt-tools-forks.sh`:
under the `shell.json` lock and through `shell_config_write` (atomic,
`DRY_RUN` honoured), only when the old id appears: bar sections get the new id
in place, and only `haseen.wooting` is then kept once, at its first place.
Every other entry stays exactly as it was, the user's own repeated strings
and identical objects included (review round 1: the first version
de-duplicated whole sections). `services` drops the old id (no service
kind), `plugins.<old>` moves to `plugins.<new>` with `enabled` and the
manifest's settings, an existing new entry winning key by key. It never
touches the plugin's directory, rule or unit, and says `haseen setup wooting
on takes it over` when the plugin's unit is installed.

### Licence review of wootingd's citations (coordinator, 2026-10-21)

Checked against the cited repositories (`gh api repos/<r>`; clones read
only):

- **clemenscodes/wootswitch** publishes no licence (GitHub: none; read at
  `247a784869e30bb6cb89406fa9726db63f899ebf`). wootingd cited it 15 times
  (device.rs:275, 301, 361, 430; proto.rs:134, 159, 165, 179, 180, 204, 206,
  214, 218, 221, 225 at `184f6fa`), most with a backtick quote of its source.
  Every quote is gone; what stays is the fact (an ordinal, the 33-byte reply,
  8 reads, 8 slots, the standard-firmware slot byte, a 100 ms settle), cited
  to a licensed source where one states it (ShayBox for 3/7/11/23 and the
  slot as parameter3, ApeironTsuka for GetVersion 1, the status bytes, the
  rgb-sdk for the frame byte of parameter3) or marked PROBED or as a plain
  fact. A five-word overlap scan of wootswitch's sources and
  `docs/hid-protocol.md` against wootingd found copied expression in
  comments only: proto.rs's "ARM response: 1 report-ID byte + 32 data
  bytes", device.rs's drain comment ("spontaneous notifications (e.g.
  profile-changed with cmd_echo 0x0b)"), its "0x66 unsupported on ARM
  firmware" and "active profile slot, 0-based". All four were rewritten. The
  code those lines document was compared with wootswitch's
  (`src/keyboard.rs` `exchange`, `profile_count`, `activate`): wootingd's
  drain uses poll(2) on its own `Reply`/`Framing` types and a
  framing-dependent echo offset; the shared part is the idea (drain, then
  read until the echo matches, at most N reads), not the expression.
- **WootingKb/wooting-rgb-sdk** and **wooting-analog-sdk** (MPL-2.0): the
  short quotes stay as citations. The rgb-sdk citations match
  `2a3f69916c4ffad2001ecde171e76070cf982cf3` (2025-12-08), the last commit
  where every cited line number holds (main `451f40dc056e…` moved lines 698
  and 798); one range was off and is corrected (device.rs's
  wooting-usb.c:437-438 → 438-440). The analog-sdk quotes match develop
  `be35a629bd79967012da4dcb731fa9e5a6d3c132`; its line numbers had moved
  (device.rs:435-448 → 438-450, 468-470 → 469-471, 254-261 → 292-298 with the
  scale at 256-258) and are updated. proto.rs's header pins each SDK to its
  commit.
- **ShayBox/Wooting-Profile-Switcher** (MIT; the repository's current name):
  every cited line holds at master `de754a6b36148a9f54074a060b62070146e7d57b`
  (also at `8101eaad68a9ca3a4d162683d7e53b7827374476`).
- **ApeironTsuka/wooting-sdk** (ISC in its package.json, no licence file; not
  in the coordinator's list, found cited in proto.rs): its status-code lines
  were off by one (keyboard.js:22-24 → 23-25) and are corrected; at
  `47e20f287a204d610d6adc3c340cec28c29498a4`.
- **Command names** (review round 1, Sonnet 5.5 on `3054a2c`): the
  constants for commands 38, 39, 48 and 55 carried wootswitch's enum names,
  and proto.rs said so ("The names are that list's"). They are renamed to
  names haseen chose for what each command answers on the 60HE+ (PROBED):
  - `CMD_RELOAD_PROFILE` (38) → `CMD_APPLY_PROFILE`;
  - `CMD_GET_KEYBOARD_PROFILE` (39) → `CMD_SLOT_CONTENT`;
  - `CMD_GET_MAPPING_PROFILE` (48) → `CMD_SLOT_KEYMAP`;
  - `CMD_GET_PROFILE_METADATA` (55) → `CMD_SLOT_NAME`.

  Two more wootswitch-only names are gone from comments and one message:
  `GetDigitalProfilesCount` (9) is now "the profile-count command", and
  `GetCurrentKeyboardProfileIndex` is now "active profile (command 11)", or
  `CMD_GET_ACTIVE_PROFILE`.

  The names that stay come from licensed sources:
  - GetVersion, GetSerial, GetDeviceConfig and ActivateProfile are
    ApeironTsuka/wooting-sdk keyboard.js:13, 14, 20 and 21;
  - `CMD_RELOAD_PROFILE_0` (7) follows ShayBox's `RELOAD_PROFILE`
    (lib.rs:16).

  Ordinals, frames and behaviour are unchanged: `cargo test --locked` still
  passes 49, and the comment-stripped `diff` against the original shows only
  the renamed identifiers and the messages above.
- No Wooting crate became a dependency: wooting-analog-sdk's Rust API (#133)
  is not on crates.io and pulls hidapi, libloading and cmake, against
  wootingd's sole-owner, one-dependency design.
- `NOTICE.md` gains a row for the port and, under factual inputs, rows for
  the two SDKs (MPL-2.0), ShayBox (MIT), ApeironTsuka (ISC) and wootswitch
  (no licence, facts only), each stating that wootingd links and vendors none
  of them.

## Evidence

- `tests/test-wooting.sh`: 286/286 at review round 1 (276/276 at
  `3054a2c`). It covers:
  - the manifest, which validates and is off by default;
  - the licence, UPSTREAM.md, NOTICE.md and AGENTS.md rows;
  - the contracts: no compat import, no Omarchy command, no colour literal,
    one marked timer;
  - the Model.js suite (269 under node);
  - the socket library, `haseen wooting` and its doctor, against
    `tools/fake-wootingd.py`. That is the original's fake, plus the daemon's
    change broadcast and its socket removal on SIGTERM.
  - `haseen setup wooting` in fixture sysroots:
    - dry runs are pure;
    - the exact root and user-manager calls;
    - idempotence;
    - the take-over, with byte-identical saved copies and an untouched
      plugin directory;
    - `off` afterwards, naming the exact saved directory, its files and the
      plugin's installer;
    - refusals, `off` leaving what is not haseen's, and the missing daemon.
  - the migration:
    - ordering after `1792531693-omarchy-path.sh`, by a range check;
    - dry run and re-run;
    - non-string entries, and the new entry winning;
    - the user's own repeated strings and identical objects kept;
    - invalid and absent files.
  - the widget and panel in qs offscreen, against a daemon that appears
    1.5 s after the shell:
    - hidden, then "Typing";
    - a switch from the panel reaching the bar through the daemon;
    - the 61-key 60HE+ with one key under travel;
    - hidden again when the daemon is killed.
- `tests/test-wootingd.sh` 25/25: the build script without cargo and with a
  cargo that does not run (skips, or fails under `HASEEN_REQUIRE_CARGO=1`),
  `cargo test --locked` (49 passed),
  the crate directory untouched by the build, the out-of-tree build into
  the tree, and the original's lifecycle checks on the built daemon.
- The suites this change touches, each run alone: test-shell 258/258,
  test-sidecar 39/39, test-wallpaper 24/24, test-adopted-tools 239/239,
  test-migrate 30/30, test-migrate-defaults 62/62, test-core 91/91,
  test-paths 22/22, test-migrate-097 31/31, test-migrate-integrations 31/31,
  test-omarchy-commands 171/171, test-install-picker 72/72, test-handlers
  89/89, test-dms-url 77/77. The full suite is left to CI.
- `tools/lint.sh` OK (795 shell, 33 Lua, 198 JSON, 334 QML, 41 Go files);
  `tools/check-docs.sh` OK.
- Review round 1 re-ran test-wooting (286/286), test-wootingd (25/25,
  `cargo test --locked` 49 passed), test-migrate (30/30) and
  test-migrate-defaults (62/62), plus `tools/lint.sh` and
  `tools/check-docs.sh`, both OK.

## Not verified

- No hardware run: no Wooting keyboard was attached; the HID path is the
  original's, unchanged and covered by its unit tests only.
- `haseen setup wooting on` was not run on luna or IO; the real udev and user
  manager calls are covered by recorded argv in fixture sysroots.
- No nested-Hyprland screenshot of the panel or board.

## Remaining (owner)

- On luna, after installing this tree: `haseen setup wooting on` (instead of
  the plugin's `install.sh`) to move the rule and unit to haseen's daemon;
  `haseen migrate` re-points `shell.json`. The plugin's copies are kept in
  `~/.local/state/haseen/wooting/`.
- wootingd's resource profile is a recorded exception to architecture §6.
  This follows the owner's choice to vendor it unchanged. §6's 2 s rule
  still covers the shell, which does not poll. While a keyboard is attached
  the daemon:
  - reads the active profile every 1.5 s (one HID round trip) and the
    profile list every 30 s (`core/wootingd/src/main.rs:50`, `:202`, loop
    at `:917`);
  - runs its analog reader for its whole life, whether or not anyone
    subscribed (`analog_thread`, `main.rs:459`, spawned at `:940`). The
    reader:
    - blocks in `poll(2)` for at most 250 ms (`ANALOG_READ_TIMEOUT_MS`,
      `main.rs:443`), so an idle keyboard wakes it about 4 times a second;
    - while keys move, decodes every analog report, up to 1 kHz, and gives
      it to `fnmap.observe` (`main.rs:528`);
    - while the analog interface is absent, retries every 1.5 s
      (`ANALOG_RETRY`, `main.rs:445`).

  Raising the 250 ms read timeout is a later option for the owner: it only
  bounds how fast an unplug is noticed.
