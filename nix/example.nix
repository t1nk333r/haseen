# nixosConfigurations.example: a minimal VM-style host used by CI to
# evaluate every haseen option. Not a template for real hardware: copy the
# haseen.* lines from nix/README.md into your own configuration instead.
{ ... }:

{
  networking.hostName = "haseen-example";
  system.stateVersion = "26.05";

  fileSystems."/" = {
    device = "/dev/disk/by-label/nixos";
    fsType = "ext4";
  };
  fileSystems."/boot" = {
    device = "/dev/disk/by-label/ESP";
    fsType = "vfat";
  };
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  # Steam (haseen.gaming) is unfree.
  nixpkgs.config.allowUnfree = true;

  haseen = {
    enable = true;
    secureboot.enable = true;
    ai = {
      enable = true;
      acceleration = "vulkan";
    };
    gaming.enable = true;
    ddc.enable = true;
  };

  users.users.demo = {
    isNormalUser = true;
    extraGroups = [
      "wheel"
      "networkmanager"
      "i2c"
    ];
    initialPassword = "demo";
  };

  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    users.demo = {
      home.stateVersion = "26.05";
      haseen = {
        enable = true;
        theme = "tokyo-night";
      };
    };
  };
}
