# nixosModules.haseen — the NixOS side of haseen. One option per layer of the
# installer (docs/architecture.md §3): `enable` is base + desktop, the rest
# are opt-in. The theme and the shell are per-user, so they live in the
# home-manager module (nix/home.nix).
#
# flake.nix imports lanzaboote's module next to this one, so
# boot.lanzaboote.* always exists; it stays inert unless secureboot.enable.
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.haseen;
  inherit (lib)
    literalExpression
    mkDefault
    mkEnableOption
    mkForce
    mkIf
    mkMerge
    mkOption
    types
    ;

  # nixpkgs removed services.ollama.acceleration; the backend is now the
  # package (nixos/modules/services/misc/ollama.nix, mkRemovedOptionModule).
  ollamaPackage = {
    cuda = pkgs.ollama-cuda;
    rocm = pkgs.ollama-rocm;
    vulkan = pkgs.ollama-vulkan;
  };
in
{
  options.haseen = {
    enable = mkEnableOption ''
      the haseen desktop: Hyprland launched through UWSM, greetd with tuigreet,
      PipeWire, XDG portals, polkit, fonts, NetworkManager and the firewall
    '';

    package = mkOption {
      type = types.package;
      default = pkgs.callPackage ./package.nix { };
      defaultText = literalExpression "pkgs.callPackage ./nix/package.nix { }";
      description = "The haseen tree (CLI + share/haseen).";
    };

    secureboot.enable = mkEnableOption ''
      Secure Boot through lanzaboote, with keys in /var/lib/sbctl. Create and
      enroll the keys by hand first (nix/README.md); enrollment must keep the
      Microsoft keys or Windows and GPU option ROMs stop booting
    '';

    ai = {
      enable = mkEnableOption "local AI: Ollama listening on 127.0.0.1 only";
      acceleration = mkOption {
        type = types.nullOr (
          types.enum [
            "cuda"
            "rocm"
            "vulkan"
          ]
        );
        default = null;
        example = "vulkan";
        description = ''
          GPU backend for Ollama, mapped to `services.ollama.package`
          (`pkgs.ollama-cuda`, `pkgs.ollama-rocm`, `pkgs.ollama-vulkan`).
          `null` keeps `pkgs.ollama`, which is CPU-only unless
          `nixpkgs.config.cudaSupport` or `rocmSupport` is set. `cuda` is
          unfree.
        '';
      };
    };

    gaming.enable = mkEnableOption "Steam, gamemode and gamescope (Steam is unfree)";
  };

  config = mkMerge [
    {
      assertions = [
        {
          assertion = cfg.gaming.enable -> cfg.enable;
          message = "haseen.gaming.enable requires haseen.enable (the gaming layer requires desktop).";
        }
      ];
    }

    (mkIf cfg.enable {
      programs.hyprland = {
        enable = true;
        withUWSM = true;
      };

      # tuigreet lists the sessions from sessionData; the default command is
      # the UWSM-managed Hyprland session, which XDG_DATA_DIRS exposes
      # (nixos/modules/services/display-managers/default.nix).
      services.greetd = {
        enable = true;
        useTextGreeter = true;
        settings.default_session = {
          user = "greeter";
          command = lib.concatStringsSep " " [
            (lib.getExe pkgs.tuigreet)
            "--time"
            "--remember"
            "--remember-user-session"
            "--asterisks"
            "--sessions ${config.services.displayManager.sessionData.desktops}/share/wayland-sessions"
            "--cmd 'uwsm start -- hyprland.desktop'"
          ];
        };
      };

      security.rtkit.enable = true;
      services.pipewire = {
        enable = true;
        alsa.enable = true;
        pulse.enable = true;
        wireplumber.enable = true;
      };

      # programs.hyprland already enables xdg.portal with the Hyprland
      # portal; gtk adds the file chooser.
      xdg.portal.extraPortals = [ pkgs.xdg-desktop-portal-gtk ];

      # The shell is the polkit agent (haseen.polkit) and reads UPower and
      # NetworkManager over D-Bus (docs/architecture.md §6).
      security.polkit.enable = true;
      services.upower.enable = true;
      networking.networkmanager.enable = true;
      networking.firewall.enable = true;

      fonts.packages = with pkgs; [
        noto-fonts
        noto-fonts-color-emoji
        nerd-fonts.jetbrains-mono
      ];

      environment.sessionVariables = {
        HASEEN_PATH = "${cfg.package}/share/haseen";
        NIXOS_OZONE_WL = "1";
      };

      # The CLI plus what the default Hyprland binds spawn by name.
      environment.systemPackages = [
        cfg.package
      ]
      ++ (with pkgs; [
        foot
        wireplumber
        brightnessctl
        grim
        slurp
        wl-clipboard
        playerctl
        hyprpicker
      ]);
    })

    (mkIf cfg.secureboot.enable {
      # lanzaboote replaces systemd-boot's installer with its own signer.
      boot.loader.systemd-boot.enable = mkForce false;
      boot.lanzaboote = {
        enable = true;
        pkiBundle = "/var/lib/sbctl";
      };
      environment.systemPackages = [ pkgs.sbctl ];
    })

    (mkIf cfg.ai.enable {
      services.ollama = {
        enable = true;
        # Loopback only: never expose the model server on the LAN.
        host = "127.0.0.1";
      }
      // lib.optionalAttrs (cfg.ai.acceleration != null) {
        package = ollamaPackage.${cfg.ai.acceleration};
      };
    })

    (mkIf cfg.gaming.enable {
      programs.steam.enable = true;
      programs.gamemode.enable = true;
      programs.gamescope = {
        enable = true;
        capSysNice = mkDefault true;
      };
    })
  ];
}
