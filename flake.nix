{
  description = "Flake for building and deploying Raspberry Pi devices and bufflehead";

  inputs = {
    nixpkgs = {
      # unstable
      url = "https://flakehub.com/f/NixOS/nixpkgs/0.1.0.tar.gz";
    };
    determinate = {
      url = "https://flakehub.com/f/DeterminateSystems/determinate/0.1";
    };
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    # ThinkPad X13s module from NixOS/nixos-hardware PR #1751 (BrainWart),
    # pinned to the PR head we tested. Switch to plain
    # "github:NixOS/nixos-hardware" once the PR is merged.
    nixos-hardware = {
      url = "github:NixOS/nixos-hardware/5a198c74fde9157ed0785ddcfb64c03e2c7915b2";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self
    , determinate
    , nixpkgs
    , colmena
    , nixos-hardware
    ,
    }:
    let
      opts = ({ config, pkgs, lib, ... }: {
        options = with lib; with types; {
          hostname = mkOption { type = str; };
          # default is bash
          # FIXME: for some reason I can't set this in common.nix
          shell = mkOption { type = str; };
        };
        config = { };
      });

      piModules = [
        "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
        ./common.nix
      ];
    in
    {
      # nix run .#colmena -- apply --on zeroCool2w
      packages.x86_64-linux.colmena = colmena.packages.x86_64-linux.colmena;
      packages.x86_64-linux.x13s-iso = self.nixosConfigurations.x13s-iso.config.system.build.isoImage;
      packages.aarch64-linux.x13s-iso = self.nixosConfigurations.x13s-iso.config.system.build.isoImage;

      nixosConfigurations = {
        x13s-iso = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            "${nixpkgs}/nixos/modules/installer/cd-dvd/installation-cd-minimal.nix"
            nixos-hardware.nixosModules.lenovo-thinkpad-x13s
            ./x13s-iso.nix
          ];
        };
        arty = nixpkgs.lib.nixosSystem {
          system = "aarch64-linux";
          modules = [
            nixos-hardware.nixosModules.lenovo-thinkpad-x13s
            ./arty.nix
          ];
        };
        bufflehead = nixpkgs.lib.nixosSystem {
          modules = [
            ./bufflehead.nix
            determinate.nixosModules.default
          ];
        };
        zero2w = nixpkgs.lib.nixosSystem {
          modules = piModules ++ [
            opts
            { hostname = "nemo"; shell = "bash"; }
            ./zero2w.nix
          ];
        };
        zeroCool2w = nixpkgs.lib.nixosSystem {
          modules = piModules ++ [
            ./zeroCool2w.nix
          ];
        };
        pi3Bplus = nixpkgs.lib.nixosSystem {
          modules = piModules ++ [
            opts
            { hostname = "nintendo"; shell = "zsh"; }
            ./pi3Bplus.nix
          ];
        };
        pi4B = nixpkgs.lib.nixosSystem {
          modules = piModules ++ [
            ./pi4B.nix
          ];
        };
      };

      # Colmena deployment configuration
      # Usage:
      #   colmena apply --on zeroCool2w
      #   colmena apply --on @pi
      colmenaHive = colmena.lib.makeHive self.outputs.colmena;
      colmena = {
        meta = {
          nixpkgs = import nixpkgs { system = "x86_64-linux"; };
          # Allow per-host nixpkgs (e.g. aarch64 for Pis)
          nodeNixpkgs = {
            arty = import nixpkgs { system = "aarch64-linux"; };
            zeroCool2w = import nixpkgs { system = "aarch64-linux"; };
            zero2w = import nixpkgs { system = "aarch64-linux"; };
            pi3Bplus = import nixpkgs { system = "aarch64-linux"; };
            pi4B = import nixpkgs { system = "aarch64-linux"; };
          };
        };

        arty = {
          deployment = {
            targetHost = "192.168.12.131";
            targetUser = "rjpc";
            tags = [ "laptop" "arm" ];
          };
          imports = [
            nixos-hardware.nixosModules.lenovo-thinkpad-x13s
            ./arty.nix
          ];
        };

        bufflehead = {
          deployment = {
            targetHost = "192.168.12.122";
            targetUser = "rjpc";
            tags = [ "desktop" ];
          };
          imports = [
            ./bufflehead.nix
            determinate.nixosModules.default
          ];
        };

        zeroCool2w = {
          deployment = {
            targetHost = "192.168.12.130";
            targetUser = "rjpc";
            # Build on deployer, push result — Pis are slow to compile
            buildOnTarget = false;
            tags = [ "pi" "zero" ];
          };
          imports = piModules ++ [ ./zeroCool2w.nix ];
        };

        zero2w = {
          deployment = {
            targetHost = "nemo";
            targetUser = "rjpc";
            buildOnTarget = false;
            tags = [ "pi" "zero" ];
          };
          imports = piModules ++ [
            opts
            { hostname = "nemo"; shell = "bash"; }
            ./zero2w.nix
          ];
        };

        pi3Bplus = {
          deployment = {
            targetHost = "nintendo";
            targetUser = "rjpc";
            buildOnTarget = false;
            tags = [ "pi" ];
          };
          imports = piModules ++ [
            opts
            { hostname = "nintendo"; shell = "zsh"; }
            ./pi3Bplus.nix
          ];
        };

        pi4B = {
          deployment = {
            targetHost = "192.168.12.139";
            targetUser = "rjpc";
            buildOnTarget = false;
            tags = [ "pi" ];
          };
          imports = piModules ++ [ ./pi4B.nix ];
        };
      };
    };
}
