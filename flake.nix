{
  description = "Flake for building and deploying Raspberry Pi devices and bufflehead";

  inputs = {
    nixpkgs = {
      # unstable¬
      url = "https://flakehub.com/f/NixOS/nixpkgs/0.1.0.tar.gz";
      # stable¬
      #url = "https://flakehub.com/f/NixOS/nixpkgs/*.tar.gz";
    };
    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    determinate = {
      url = "https://flakehub.com/f/DeterminateSystems/determinate/0.1";
    };
    deploy-rs = {
      url = "github:serokell/deploy-rs";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self
    , determinate
    , nixpkgs
    , home-manager
    , deploy-rs
    ,
    }: rec {
      opts = ({ config, pkgs, lib, ... }:
        {
          options = with lib; with types; {
            hostname = mkOption { type = str; };
            # default is bash
            # FIXME: for some reason I can't set this in common.nix
            shell = mkOption { type = str; };
          };
          config = { };
        });
      nixosConfigurations = {
        bufflehead = nixpkgs.lib.nixosSystem {
          modules = [
            opts
            {
              hostname = "bufflehead";
              shell = "zsh";
            }
            ./bufflehead.nix
            determinate.nixosModules.default
          ];
        };
        zero2w = nixpkgs.lib.nixosSystem {
          modules = [
            opts
            {
              hostname = "nemo";
              shell = "bash";
            }
            "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
            ./common.nix
            ./zero2w.nix
          ];
        };
        zeroCool2w = nixpkgs.lib.nixosSystem {
          modules = [
            "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
            ./common.nix
            ./zeroCool2w.nix
          ];
        };
        pi3Bplus = nixpkgs.lib.nixosSystem {
          modules = [
            opts
            {
              hostname = "nintendo";
              shell = "zsh";
            }
            "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
            ./common.nix
            ./pi3Bplus.nix
          ];
        };
        pi4B = nixpkgs.lib.nixosSystem {
          modules = [
            "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
            ./common.nix
            home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.users.rjpc = import ./home.nix;
            }
            ./pi4B.nix
          ];
        };
      };

      deploy = {
        user = "root";
        nodes = {
          bufflehead = {
            hostname = "bufflehead";
            profiles.system.path =
              deploy-rs.lib.x86_64-linux.activate.nixos self.nixosConfigurations.bufflehead;
          };
          zero2w = {
            hostname = "nemo";
            profiles.system.path =
              deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.zero2w;
          };
          zeroCool2w = {
            hostname = "zerocool";
            profiles.system.path =
              deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.zeroCool2w;
          };
          pi3Bplus = {
            hostname = "nintendo";
            profiles.system.path =
              deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.pi3Bplus;
          };
          pi4B = {
            hostname = "madison";
            profiles.system.path =
              deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.pi4B;
          };
        };
      };
      checks = builtins.mapAttrs (system: deployLib: deployLib.deployChecks self.deploy) deploy-rs.lib;
    };
}
