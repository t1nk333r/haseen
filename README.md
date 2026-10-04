# haseen

حصين (*haseen*, "fortified"): a clean, low-resource desktop that installs on
top of **CachyOS** (plain Arch works too; NixOS uses the flake). It is built on
Hyprland (Lua config) and a small Quickshell shell of its own, and it can load
add-ons made for Omarchy and DankMaterialShell.

- **Clean.** Every part is an opt-in layer. The default is `base desktop theme shell`.
- **No clutter.** One thin bar. Everything else (launcher, notifications, AI, session) is a panel you open on demand.
- **Light.** The idle shell measures 162–178 MiB RSS with ~0 % CPU on the reference laptop (omarchy-shell beside it: 630 MiB).
- **Extendable with AI.** Plugins are a `manifest.json` plus QML, checked against a JSON schema (`haseen plugin new/validate/enable`). An agent skill (`haseen ai skill install`) teaches coding agents to do this safely.
- **Local AI.** Ollama or llama.cpp, listening on 127.0.0.1 only, with a chat panel in the shell.
- **Secure Boot for Windows dual boot.** sbctl keys are enrolled **with** Microsoft's (2011 and 2023 CAs) and the firmware's, so Windows and anti-cheat keep working. The Limine config hash is enrolled, and a pacman hook re-signs after updates.
- **Omarchy and DMS add-ons.** Omarchy `colors.toml` themes install unchanged. Omarchy and DMS bar plugins load through compat adapters, or DMS can replace the haseen shell entirely (`haseen shell use dms`).

## Install (CachyOS / Arch)

Install CachyOS with its own installer (disk, LUKS, Limine), then:

```sh
git clone <this repo> haseen && cd haseen
./install.sh --dry-run          # print the full plan, change nothing
./install.sh                    # base desktop theme shell
haseen layer apply ai gaming    # optional layers
haseen secureboot setup         # interactive; firmware must be in Setup Mode
```

The installer copies the tree to `/usr/local` (`bin/haseen*`, `share/haseen/`)
and applies layers through `haseen layer apply`. Every command that changes the
system accepts `--dry-run`.

| Layer | What it adds |
|---|---|
| `base` | essentials, ufw, snapper check |
| `desktop` | Hyprland (Lua) + uwsm, greetd/tuigreet (only if no display manager is enabled), portals, fonts, GPU session env |
| `theme` | theme pipeline, five stock themes, `haseen theme set/install` |
| `shell` | the haseen Quickshell shell as `haseen-shell.service` |
| `secureboot` | sbctl, signing hook; `haseen secureboot setup` enrolls the keys |
| `ai` | Ollama (GPU-matched) or llama.cpp on loopback; `haseen ai chat/models/pull` |
| `dms` | DankMaterialShell, available to swap in with `haseen shell use dms` |
| `gaming` | CachyOS gaming packages (Steam, gamemode, MangoHud, Proton) |

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
