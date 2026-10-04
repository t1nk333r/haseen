# Plan 017: Install/Remove (Flatpak-first) and Update

## Status

- **Priority**: P1
- **Effort**: L
- **Risk**: MEDIUM
- **Depends on**: 005 010 011
- **Category**: shell
- **Planned at**: 2026-10-04, owner request (second feature round)
- **State**: DONE 2026-10-04. All 30 Flathub refs returned HTTP 200. Install and remove were tested as dry runs only, with no real installs.

## Why this matters

The owner chose Flatpak-first installs (2026-10-04): apps come from Flathub, and pacman/AUR are used only for system pieces. Update covers system/firmware/time/password/restart/reset.

## Execution record

### What changed

- **Catalogue**: `share/haseen/default/catalog.json`, 70 entries in 8 categories (browser, editor, terminal, ai, gaming, service, font, development). These cover Omarchy's `install.*` categories (`/tmp/ref/omarchy/default/omarchy/omarchy-menu.jsonc:197-287`).
  - Every entry has `id`, `category`, `label`, `icon` (a Nerd Font glyph, shown by `Glyph.qml`), `source` (`flatpak|pacman|aur|mise`) and `ref`, plus an optional `when` bash guard.
  - Some entries carry extras: `family` (fonts), `layer` (Steam goes through `layers/gaming`), `needs` (pacman build deps for a mise toolchain) and `container` (Docker databases; `ref` is then the `docker` package).
  - Plain JSON, not JSONC, so `tools/lint.sh`'s `jq empty` covers it.
  - The format was sent to Menu, which renders it with `haseen install app --installed` (one call, file reads only) and the actions `haseen install|remove app <id>`.
- **Flatpak-first.** Browsers, GUI editors, AI apps, gaming launchers and services (1Password, Bitwarden, Dropbox, Spotify, Signal, Discord, Obsidian) are all Flathub apps (30 refs).
- **pacman/AUR are used only for system pieces and CLIs**, each for a reason:
  - terminals (alacritty, foot, ghostty, kitty) and terminal editors (helix, neovim, vim): a Flatpak cannot put `hx`/`nvim` on PATH;
  - Nerd Fonts (7 `ttf-*-nerd`);
  - daemons: `tailscale` (+ `tailscaled.service`), AUR `nordvpn-bin` (+ `nordvpnd`, nordvpn group), `docker docker-compose` (+ `docker.socket`, no docker group because it is root-equivalent);
  - AUR `xpadneo-dkms` (a kernel module; writes `/etc/modprobe.d/haseen-xpadneo.conf` and `/etc/modules-load.d/haseen-xpadneo.conf`, adds the input group);
  - AUR `cursor-bin`: Cursor is not on Flathub. `co.anysphere.cursor`, `com.cursor.Cursor` and `io.github.cursor.Cursor` all return 404, and a search for "cursor" has no hit.
- **Steam is pacman via `haseen layer apply gaming`, not the Flatpak.**
  - The gaming layer already does what Steam needs: it checks `[multilib]`, installs 32-bit Vulkan drivers matched to the GPU and the installed NVIDIA branch, uses `cachyos-gaming-meta` on CachyOS, and handles gamemode group membership (`share/haseen/layers/gaming/layer.sh:34-66`).
  - The Flatpak would duplicate that runtime, could not see the host gamescope/gamemode setup, and still needs host udev rules.
- **Dev toolchains use mise** (17 tools, all present in `mise registry`, mise 2026.9.1): node@lts, bun, deno, python+uv, go, rust@stable, zig+zls, ruby (+libyaml), java, dotnet, erlang+elixir, clojure (+rlwrap), scala+scala-cli.
  - Docker DBs (PostgreSQL 18, MySQL 8.4, MariaDB 11.8, Redis 7, MongoDB) run as containers bound to 127.0.0.1, with the settings from `omarchy-install-docker-dbs`.
- **Commands**, one file per verb, with shared code in two libraries:
  - `bin/haseen-install`: `package|aur [NAME…]` (fzf picker when no NAME), `flatpak ID`, `app NAME`, `font NAME`, `dev LANG`, `app --list [cat]`, `app --installed [ID]`. `app` resolves an id, a label or a ref, case-insensitively. A font install ends with `haseen font set <family>` when Menu's `bin/haseen-font-set` exists (in dry-run it is printed, not called).
  - `bin/haseen-remove`: the same forms. `pacman -Rns`; `flatpak uninstall` in the user scope, falling back to system scope; `mise unuse --global`; `docker rm -f` for DB containers, which leaves the engine alone.
  - `bin/haseen-update [system|firmware]`:
    - `system`: `sudo pacman -Syu`, then `paru|yay -Sua`, then `flatpak update --user` (plus `--system` when `/var/lib/flatpak/app` holds apps), then `haseen hook run post-update`.
    - `firmware`: installs fwupd if missing, then `fwupdmgr refresh --force`, `get-updates`, `sudo fwupdmgr update`. With Secure Boot enabled and sbctl present it signs `fwupdx64.efi` into `.signed`, so capsule updates boot under haseen's keys.
  - `bin/haseen-time sync|timezone [ZONE]`: timedatectl. The zone is picked with fzf and must be a file under zoneinfo; a path climb is refused.
  - `bin/haseen-password user|drive`:
    - `drive` finds the root LUKS device from `/proc/self/mountinfo` and `/sys/block/dm-*/{dm/name,dm/uuid,slaves}`, including LVM-on-LUKS. It shows a warning (current passphrase, other slots and tokens unaffected, data loss if forgotten, header backup command), then requires the typed word `CHANGE` (`confirm_typed`; `--yes` does not bypass it).
    - It then runs `sudo cryptsetup luksChangeKey --verify-passphrase [--pbkdf argon2id on LUKS2] <dev>`.
  - `bin/haseen-restart audio|wifi|bluetooth|trackpad|shell`:
    - audio: the PipeWire user units;
    - wifi: rfkill + nmcli, or a restart of iwd;
    - bluetooth: rfkill + `bluetooth.service`;
    - trackpad: `modprobe -r` + `modprobe` of whichever of `i2c_hid_acpi intel_quicki2c psmouse` is loaded;
    - shell: `haseen shell restart`.
  - `bin/haseen-refresh hyprland|shell|nightlight`. Each one makes `<file>.bak.<timestamp>` before replacing anything, asks `confirm` (`--yes` skips it), and prints the diff afterwards.
    - hyprland: reseeds `~/.config/hypr/*` from `default/hypr/user/`, then `hyprctl reload`.
    - shell: reseeds `~/.config/haseen/shell.json` from the shell layer's seed. Plugins are never touched.
    - nightlight: Ambient's plugin seeds no file, so this deletes `plugins."haseen.nightlight".settings` from shell.json (with a backup) and calls `haseen shell ipc nightlight refresh`.
- **`share/haseen/lib/catalog.sh`** (approved by Main):
  - catalogue lookups;
  - install-state probes that read only files (the pacman local db, `~/.local/share/flatpak/app`, `/var/lib/flatpak/app`, mise `installs/`);
  - the per-source install/remove dispatch and the per-entry post-install steps.
- **`share/haseen/lib/terminal.sh`** (Main asked me to own it as the shared helper; Menu and Trigger were told the API):
  - `in_floating_terminal "$@"` re-execs the script in `$TERMINAL` (foot fallback) with app-id `haseen.floating` when stdin is not a TTY. The window holds open with `[done]` / `[failed: exit N] press Enter to close`.
  - It stays inline for `--dry-run`/`--help`, for `DRY_RUN`, and for `HASEEN_INLINE=1` (tests).
  - `floating_terminal_exec` and `floating_terminal_argv` are the generic forms. Each terminal gets its own app-id flag (foot `--app-id`, kitty/ghostty `--class=`, alacritty `--class`, wezterm `start --class`).
- **Layer `flatpak`** (`share/haseen/layers/flatpak/{layer.sh,packages.txt}`): it requires desktop, installs `flatpak`, and adds Flathub with `flatpak remote-add --user --if-not-exists flathub https://dl.flathub.org/repo/flathub.flatpakrepo`.
  - **User scope, why**: app installs, updates and removals from the menu need no root and no polkit prompt.
  - Arch's flatpak package already ships `/usr/share/flatpak/remotes.d/flathub.flatpakrepo` for the *system* scope (archlinux.org file list, 2026-10-04), which does not help the user scope.
  - The package's `/usr/lib/systemd/user-environment-generators/60-flatpak` (`pacman -Qo` on the reference machine) puts the user exports on `XDG_DATA_DIRS` for uwsm sessions.
  - `layer_remove` deletes the user remote only when no user app is left.
- **Ported from Omarchy (MIT; header notices in each file)**: `omarchy-pkg-install`, `-pkg-aur-install`, `-pkg-remove`, `-update-firmware`, `-update-time`, `-menu-timezone`, `-drive-password`, `-restart-{audio,wifi,bluetooth,trackpad}` and `-refresh-config`.

### Evidence

- **Flathub, every flatpak ref in the catalogue**, checked 2026-10-04T12:53Z with `curl https://flathub.org/api/v2/appstream/<id>`: **30/30 returned HTTP 200**.
  - Browsers: org.mozilla.firefox, com.google.Chrome, org.chromium.Chromium, com.microsoft.Edge, com.brave.Browser, app.zen_browser.zen.
  - Editors: com.visualstudio.code, com.vscodium.codium, dev.zed.Zed, com.sublimetext.three, org.gnu.emacs.
  - AI: com.jeffser.Alpaca, ai.jan.Jan, io.gpt4all.gpt4all, io.github.qwersyk.Newelle, ai.lmstudio.lm-studio, net.mkiol.SpeechNote.
  - Gaming: net.lutris.Lutris, com.heroicgameslauncher.hgl, com.usebottles.bottles, org.libretro.RetroArch, com.mojang.Minecraft, org.prismlauncher.PrismLauncher.
  - Services: com.onepassword.OnePassword, com.bitwarden.desktop, com.dropbox.Client, com.spotify.Client, org.signal.Signal, com.discordapp.Discord, md.obsidian.Obsidian.
  - The date is recorded in the catalogue as `flathubVerified`.
- **pacman refs**: `pacman -Si` 2026-10-04 found every one.
  - In extra: alacritty, foot, ghostty, kitty, helix, vim, neovim, tailscale, docker, docker-compose, mise, fwupd, fzf, flatpak, libyaml, rlwrap, and all 7 `ttf-*-nerd` fonts.
  - steam is in multilib.
- **AUR refs**: the AUR RPC v5 on 2026-10-04 returned cursor-bin 3.23.12-1, xpadneo-dkms 0.10.4-1 and nordvpn-bin 5.4.0-1.
- **Tests**: `tests/run.sh tests/test-catalog.sh` passes **125/125**, and together with `test-core.sh` and `test-desktop.sh` **287/287**. `tools/check-docs.sh` is OK. The test covers:
  - catalogue validity: unique ids, known sources, required fields, categories exist, no web apps or Xbox Cloud, ref syntax, fonts have a family, browsers only Flatpak;
  - dry-run dispatch for every source (flatpak, pacman, aur, mise, container, layer) and every command;
  - file-only install detection;
  - the LUKS gate: a wrong word, `--yes` and an empty answer all exit 1 with no STUB-CALLED, the correct word reaches the `cryptsetup` stub, LVM-on-LUKS1 drops argon2, and a plain root is refused;
  - a real refresh in the scratch HOME (backup content checked, nightlight settings dropped and the rest kept);
  - the terminal re-exec (foot/kitty argv);
  - dry-run purity, and nothing written under HOME.
- **Lint**: `bash -n` and `/tmp/tools/shellcheck --severity=warning -x` are clean on all 11 shell files. `jq empty catalog.json` passes. There is no QML in this plan.
- **Live smoke** (reference machine, read-only):
  - `haseen password drive --dry-run` found `/dev/nvme0n1p2` LUKS2 under `/dev/mapper/root[/@]`, which matches `lsblk` and `findmnt`.
  - `haseen install app --installed` printed zen neovim foot steam tailscale node go docker.
  - The update, firmware, timezone, refresh and trackpad dry-runs printed the expected plans.
  - `haseen time timezone` started with stdin `</dev/null` opened foot with class `haseen.floating`, title `haseen`, running the fzf zone picker (grim screenshot viewed). That foot PID was then killed, so nothing was selected or set.
  - The window was tiled, not floating: the window rule is an integration request.
- **Idle RSS**: unchanged. This plan adds no QML, plugin or service to the shell.

### Rejected

- **GeForce NOW**: not on Flathub (`com.nvidia.geforcenow` returns 404). NVIDIA installs it with a vendor `.bin` that adds its own remote, and running an unsigned vendor installer from the menu was rejected.
- **ChatGPT and Claude desktop**: no Linux build on Flathub. The AUR `claude-desktop` repackages the Windows build unofficially; `openai-codex-desktop` is not in the AUR.
- **Ollama**: left to `haseen layer apply ai` (plan 006), which picks the CUDA/ROCm build. A catalogue entry with a fixed `ollama` ref would mis-detect the `ollama-cuda` and `ollama-rocm` variants.
- **Not ported**:
  - PHP, Laravel, Symfony and Phoenix: mise's PHP compiles from source, or Omarchy's alias points at a third-party static build;
  - OCaml: Omarchy pipes curl into sh for opam;
  - Battle.net: a Lutris script;
  - Brave Origin: not on Flathub; a search for "brave" returns only com.brave.Browser;
  - MSSQL: a fixed SA password.
- **Docker DB install detection**: impossible without root, since the docker socket and `/var/lib/docker` are root-only. DB entries never count as installed, and `haseen remove app <db>` still works.
- **System-scope Flatpak**: rejected because it needs a polkit prompt for every install and update.
- **A fifth `docker` source**: rejected to keep the four contract sources. Containers are `pacman` entries with `ref: docker` plus `container`.
- **Omarchy's USB-audio reset in `restart audio`**: not ported. It needs usbreset and root for a rare failure, and replugging the device does the same.
- **i2c unbind/rebind through sysfs**: replaced by `modprobe` reloads, which keep `sudo` inside `run_root` with no shell redirection.
