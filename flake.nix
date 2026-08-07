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
  };

  outputs =
    { self
    , determinate
    , nixpkgs
    , colmena
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

      nixosConfigurations = {
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
      # Usage from bufflehead:
      #   nix run .#colmena -- apply --on zeroCool2w
      #   nix run .#colmena -- apply --on @pi
      colmena = {
        meta = {
          nixpkgs = import nixpkgs { system = "x86_64-linux"; };
          # Allow per-host nixpkgs (e.g. aarch64 for Pis)
          nodeNixpkgs = {
            zeroCool2w = import nixpkgs { system = "aarch64-linux"; };
            zero2w = import nixpkgs { system = "aarch64-linux"; };
            pi3Bplus = import nixpkgs { system = "aarch64-linux"; };
            pi4B = import nixpkgs { system = "aarch64-linux"; };
          };
        };

        bufflehead = {
          deployment = {
            targetHost = "bufflehead";
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
