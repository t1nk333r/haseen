# haseen on NixOS

`install.sh` targets CachyOS and Arch, and it refuses to run on NixOS. On NixOS
you get the same desktop from this flake:

| Output | What it is |
|---|---|
| `packages.<system>.haseen` | `bin/` + `share/haseen`; every `haseen*` command is wrapped with `HASEEN_PATH=$out/share/haseen` and jq, curl, coreutils, quickshell, … on `PATH` |
| `overlays.default` | adds `pkgs.haseen` |
| `nixosModules.haseen` | system side: `haseen.enable`, `.secureboot`, `.ai`, `.gaming` |
| `homeManagerModules.haseen` | user side: the shell service, the theme, `~/.config/hypr/hyprland.lua` |
| `nixosConfigurations.example` | CI host with every option on (`nix/example.nix`) |

The installer layers map to options as follows. `base` + `desktop` →
`haseen.enable`; `theme` → `haseen.theme` (home-manager); `shell` →
`haseen.shell.enable` (home-manager); `secureboot`, `ai` and `gaming`
→ the options of the same name. `dms` has no option: nixpkgs ships its own
`programs.dms-shell` module.

## Flake inputs

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    haseen = {
      url = "git+file:///path/to/haseen"; # your clone of this repository
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.home-manager.follows = "home-manager";
    };
  };

  outputs = { nixpkgs, home-manager, haseen, ... }: {
    nixosConfigurations.myhost = nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [
        ./configuration.nix
        haseen.nixosModules.haseen
        home-manager.nixosModules.home-manager
        { home-manager.sharedModules = [ haseen.homeManagerModules.haseen ]; }
      ];
    };
  };
}
```

haseen needs nixpkgs with Hyprland ≥ 0.56 (Lua config) and Quickshell ≥ 0.3,
which means `nixos-unstable` as of 2026-10. The lanzaboote module is imported by
`nixosModules.haseen` and does nothing until `haseen.secureboot.enable` is set.

## Minimal `configuration.nix`

```nix
{ ... }:
{
  imports = [ ./hardware-configuration.nix ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  haseen = {
    enable = true;               # Hyprland (UWSM), greetd + tuigreet, PipeWire,
                                 # portals, polkit, fonts, NetworkManager, firewall
    # secureboot.enable = true;  # after the steps below
    # ai = { enable = true; acceleration = "vulkan"; };  # null | "cuda" | "rocm" | "vulkan"
    # gaming.enable = true;      # Steam (unfree), gamemode, gamescope
  };

  users.users.you = {
    isNormalUser = true;
    extraGroups = [ "wheel" "networkmanager" ];
  };

  home-manager.users.you = {
    home.stateVersion = "26.05";
    haseen = {
      enable = true;             # CLI, haseen-shell.service, hyprland.lua
      theme = "tokyo-night";     # optional; runs `haseen theme set` on activation
    };
  };

  system.stateVersion = "26.05";
}
```

Notes:

- **Hyprland config.** home-manager owns `~/.config/hypr/hyprland.lua`, which
  loads `share/haseen/default/hypr/init.lua` from the store. Your own settings
  go in `monitors.lua`, `bindings.lua` or `local.lua` in the same directory,
  which are plain files you edit, or in `haseen.hypr.extraConfig`. Set
  `haseen.hypr.enable = false` to manage the file yourself. Don't also enable
  home-manager's `wayland.windowManager.hyprland`, which writes its own
  config.
- **Theme.** `haseen.theme = null` (the default) leaves the theme to
  `haseen theme set` at runtime. A name re-applies it on every switch.
- **AI.** Ollama listens on `127.0.0.1:11434` only. nixpkgs removed
  `services.ollama.acceleration`, so `haseen.ai.acceleration` selects
  `pkgs.ollama-cuda`, `pkgs.ollama-rocm` or `pkgs.ollama-vulkan` as
  `services.ollama.package`. `cuda` is unfree.
- **Gaming.** Steam is unfree. Set `nixpkgs.config.allowUnfree = true` or an
  `allowUnfreePredicate` that allows it.

## Secure Boot (lanzaboote)

This uses the same key model as the `secureboot` layer
(`docs/architecture.md` §8). You create your own PK/KEK/db and enroll them
**together with the Microsoft and firmware-builtin keys**. Without the Microsoft
keys, Windows, Microsoft-signed GPU option ROMs and anti-cheat that requires
Secure Boot all stop working.

1. Boot NixOS in UEFI mode with systemd-boot and Secure Boot **off**.
2. Create the keys. They go in `/var/lib/sbctl`, which is what
   `haseen.secureboot.enable` sets as `boot.lanzaboote.pkiBundle`:

   ```sh
   sudo sbctl create-keys
   ```

3. Set `haseen.secureboot.enable = true;` and run `sudo nixos-rebuild switch`.
   lanzaboote replaces systemd-boot's installer (the module forces
   `boot.loader.systemd-boot.enable = false`) and signs the boot files.
4. Check the result with `sudo sbctl verify`. Everything lanzaboote installed
   should be signed. The `*-bzImage.efi` kernel files under `EFI/nixos` show as
   unsigned; that is expected, because lanzaboote's signed stub verifies them.
5. **Windows dual boot: BitLocker.** Enrolling changes `db`, and that changes
   PCR 7, so BitLocker will ask for its recovery key once at the next Windows
   boot. Have the recovery key at hand, or suspend BitLocker in Windows
   (`manage-bde -protectors -disable C: -RebootCount 1`) before you go on.
6. Reboot into the firmware setup and put Secure Boot in **Setup Mode**
   ("Reset to Setup Mode" or "Clear Secure Boot keys"). Back in NixOS,
   `sudo sbctl status` must say `Setup Mode: ✓ Enabled`.
7. Enroll your keys together with Microsoft's and the firmware's:

   ```sh
   sudo sbctl enroll-keys --microsoft --firmware-builtin
   ```

8. Reboot, turn Secure Boot on in the firmware, and confirm with
   `bootctl status` (`Secure Boot: enabled (user)`).

If the machine fails to boot, turn Secure Boot off in the firmware. NixOS
still boots, and you can redo the steps from step 4.

## Checking the flake

```sh
nix flake check --no-build
nix eval --raw .#nixosConfigurations.example.config.system.build.toplevel.drvPath
nix build .#haseen
```

Without root, [nix-portable](https://github.com/DavHau/nix-portable) works
(`NP_RUNTIME=bwrap`). Use a `path:` flake URL (`path:$PWD`) while the files
are not yet tracked by git.
