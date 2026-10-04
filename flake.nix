{
  description = "haseen: a clean, low-resource Hyprland + Quickshell desktop (NixOS side)";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    lanzaboote = {
      url = "github:nix-community/lanzaboote";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # Only nixosConfigurations.example uses it, to evaluate the home-manager
    # module in CI; consumers bring their own home-manager.
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    {
      self,
      nixpkgs,
      lanzaboote,
      home-manager,
      ...
    }:
    let
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: nixpkgs.lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});
    in
    {
      packages = forAllSystems (pkgs: rec {
        haseen = pkgs.callPackage ./nix/package.nix { };
        default = haseen;
      });

      overlays.default = final: _prev: {
        haseen = final.callPackage ./nix/package.nix { };
      };

      nixosModules = {
        haseen = {
          imports = [
            lanzaboote.nixosModules.lanzaboote
            ./nix/nixos.nix
          ];
        };
        default = self.nixosModules.haseen;
      };

      homeManagerModules = {
        haseen = ./nix/home.nix;
        default = self.homeManagerModules.haseen;
      };

      # CI: a minimal VM-style host with every haseen option switched on.
      nixosConfigurations.example = nixpkgs.lib.nixosSystem {
        system = "x86_64-linux";
        modules = [
          self.nixosModules.haseen
          home-manager.nixosModules.home-manager
          {
            home-manager.sharedModules = [ self.homeManagerModules.haseen ];
          }
          ./nix/example.nix
        ];
      };
    };
}
