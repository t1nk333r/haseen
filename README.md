# haseen

[![ci](https://github.com/t1nk333r/haseen/actions/workflows/ci.yml/badge.svg)](https://github.com/t1nk333r/haseen/actions/workflows/ci.yml)

حصين (*haseen*, "fortified"): a clean, low-resource desktop that installs on
top of **CachyOS** (plain Arch works too; NixOS uses the flake). It is built on
Hyprland (Lua config) and a small Quickshell shell of its own, and it can load
add-ons made for Omarchy and DankMaterialShell.

- **Clean.** Every part is an opt-in layer. The default is `base chaotic omarchy-repo desktop theme shell`.
- **No clutter.** One thin bar that flows into a slim frame around the screen. Double-click the bar to make it transparent; its text then takes a colour that contrasts with the wallpaper. The tray hides behind a chevron until you hover over it or pin it. Indicators (privacy dots, stay-awake, do-not-disturb) appear only while something is active. Everything else is a panel opened on demand: menu, launcher, notifications, AI, clipboard, calendar, Wi-Fi, Bluetooth.
- **Light.** The idle shell, with every default widget, measures 176 MiB RSS / 123 MiB PSS with ~0 % CPU on the reference laptop (omarchy-shell beside it: 630 MiB). Sampling lives in one small Go daemon (`haseen-sidecar`), not in QML timers: several widgets share one sampler, nothing is read while nothing is shown, and without the daemon the features that need it hide.
- **Extendable with AI.** Plugins are a `manifest.json` plus QML, checked against a JSON schema (`haseen plugin new/validate/enable`). An agent skill (`haseen ai skill install`) teaches coding agents to do this safely.
- **Local AI.** Ollama or llama.cpp, listening on 127.0.0.1 only, with a chat panel in the shell.
- **Secure Boot for Windows dual boot.** sbctl keys are enrolled **with** Microsoft's (2011 and 2023 CAs) and the firmware's, so Windows and anti-cheat keep working. The Limine config hash is enrolled, and a pacman hook re-signs after updates. `haseen boot list` shows what the firmware can start and the power menu has a row per other system: it sets `BootNext` and reboots, so Windows starts once without touching the boot order.
- **Omarchy and DMS add-ons.** All 22 Omarchy themes are included; their backgrounds are fetched on first use from a pinned commit. Omarchy's menu, workspaces and ttfx screensaver are ported. The compatibility host supports Omarchy bar widgets, panels, services and overlays while preserving their original directories; DMS bar-widget compatibility is unchanged. Imported plugins are opt-in, not sandboxed, and may require their original helper/config backends. DMS can replace the shell entirely (`haseen shell use dms`).
- **Everyday tools.** Screenshots, screen recording, OCR, QR, colour picker, emoji, reminders, night light, stay awake, do not disturb, CPU/RAM/GPU usage, iPhone-style privacy dots (green camera, orange mic, red recording/share, blue location), media, weather (off by default), clipboard history, Flatpak-first app installs.
- **Keys you can see.** `SUPER + /` opens a searchable sheet of the bindings the compositor actually has, grouped by the section they were written under (`haseen keybinds` prints the same in a terminal). Menu Learn › Keybindings lists them Omarchy's way, and Enter runs the one you pick; Learn › Tmux lists tmux's keys with your config.
- **Upgrades that are not reinstalls.** `haseen migrate` runs one-off upgrade steps once per user and records them in your state dir; a login notice offers to run what is pending.
- **Knows your machine.** `haseen hw match` reads the firmware's DMI identity and lists the quirks that apply to it, from one table; `haseen hw apply` runs each matched fix once and records it, and a quirk nobody has written yet is reported, not hidden.
- **Defaults:**
  - Theme: `haseen`, haseen's own theme: HANCORE's Greek Noir with the "akane" border wipe (formerly `greek-noir-akane`, which still works as a name).
  - Cursor: Bibata Modern Ice at 20 px.
  - Notifications: **haseen.pager**, a stacking, grouping notification daemon with snooze, ported from omapager.
  - Prayer times: **haseen.prayers**, calculated offline with Umm al-Qura and Hijri dates, ported from omaprayers. It defaults to the city centre of Riyadh; set your own location in its panel.

## Install (CachyOS / Arch)

Install CachyOS with its own installer (disk, LUKS, Limine), then:

```sh
git clone <this repo> haseen && cd haseen
./install.sh --dry-run          # pick, then print the full plan; change nothing
./install.sh                    # pick layers and optional steps, then install
./install.sh --yes              # no questions: base chaotic omarchy-repo desktop theme shell
haseen layer apply ai gaming    # optional layers, later
haseen secureboot setup         # interactive; firmware must be in Setup Mode
```

At a terminal the installer first offers a picker: the default layers start
ticked, while the optional layers (secureboot, ai, dms, gaming, flatpak) and setup
steps (keyd, fingerprint, geoclue, dotfiles) start off. It uses gum when
installed, else a numbered list. The choice is saved to
`~/.config/haseen/install.toml`, and the next run offers to reuse it. Piped,
`--yes` and `--layers a,b,c` runs ask nothing; `--pick` forces the picker.

The installer copies the tree to `/usr/local` (`bin/haseen*`, `share/haseen/`)
and applies layers through `haseen layer apply`. Every command that changes the
system accepts `--dry-run`.

Coming from Omarchy? `haseen import omarchy --dry-run` shows how your bar,
add-on plugins, idle times, branding, hooks, themes and Hyprland overrides
translate, and lists what has no haseen equivalent; run it without
`--dry-run` to write them. Omarchy's own files are only read.

| Layer | What it adds |
|---|---|
| `base` | essentials, ufw, snapper check |
| `chaotic` | Chaotic-AUR. Packages come from the official/CachyOS repos first, then Chaotic-AUR, then Omarchy's repo (all prebuilt); the AUR is the last resort |
| `omarchy-repo` | Omarchy's repo, last in pacman.conf, as a source for leaf packages like ttfx. Omarchy itself (`omarchy`, `omarchy-settings`) is never installed |
| `desktop` | Hyprland (Lua) + uwsm, greetd/tuigreet (only if no display manager is enabled), portals, fonts, GPU session env |
| `theme` | theme pipeline, the 22 Omarchy themes plus haseen's own (the default), background fetch + `haseen-background.service`, `haseen theme set/install/bg` |
| `flatpak` | Flathub (per user); `haseen install app …` is Flatpak-first |
| `shell` | the haseen Quickshell shell as `haseen-shell.service` |
| `secureboot` | sbctl, signing hook; `haseen secureboot setup` enrolls the keys |
| `ai` | Ollama (GPU-matched) or llama.cpp on loopback; `haseen ai chat/models/pull` |
| `dms` | DankMaterialShell, available to swap in with `haseen shell use dms` |
| `gaming` | CachyOS gaming packages (Steam, gamemode, MangoHud, Proton) |
| `vapt` | optional owner tool inventory and native/COAE environments; explicit groups, no AUR or Omarchy dependency, no assessment execution ([details](docs/vapt.md)) |

`haseen commands` lists everything; `haseen doctor` shows what was detected and
how each layer is doing.

## NixOS

See [`nix/README.md`](nix/README.md): `nixosModules.haseen` (with lanzaboote
for Secure Boot) and `homeManagerModules.haseen`.

## Docs

- [`docs/architecture.md`](docs/architecture.md): the contract between parts
- [`docs/decisions/`](docs/decisions/): ADRs
- [`plans/README.md`](plans/README.md): the engineering record and its status
- [`AGENTS.md`](AGENTS.md): conventions and gates (`tools/lint.sh`, `tests/run.sh`, `tools/check-docs.sh`)

## Status

0.1.0-dev. Covered so far:
- Fixture-tested.
- The shell was run live next to an existing session.
- The flake was evaluated and built.

Not run yet: a real install on a CachyOS machine, Secure Boot enrollment on real firmware, and greetd login (plan 014).

## License

MIT. Third-party code and references are listed in [`NOTICE.md`](NOTICE.md).
