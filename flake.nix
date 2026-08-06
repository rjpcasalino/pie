{
  description = "Flake for building and deploying Raspberry Pi devices and bufflehead";

  inputs = {
    nixpkgs = {
      # unstable¬
      # url = "https://flakehub.com/f/NixOS/nixpkgs/0.1.0.tar.gz";
      # stable¬
      url = "https://flakehub.com/f/NixOS/nixpkgs/*.tar.gz";
    };
    home-manager = {
      url = "github:nix-community/home-manager/release-24.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    determinate = {
      url = "https://flakehub.com/f/DeterminateSystems/determinate/0.1";
    };
    colmena = {
      url = "github:zhaofengli/colmena";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    agenix = {
      url = "github:ryantm/agenix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    { self
    , determinate
    , nixpkgs
    , home-manager
    , colmena
    , agenix
    ,
    }:
    let
      # Shared aarch64 Pi modules used by colmena nodes.
      piModules = [
        "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
        agenix.nixosModules.default
        ./common.nix
      ];

      opts = ({ config, pkgs, lib, ... }: {
        options = with lib; with types; {
          hostname = mkOption { type = str; };
          # default is bash
          # FIXME: for some reason I can't set this in common.nix
          shell = mkOption { type = str; };
        };
        config = { };
      });
    in
    {
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
          modules = piModules ++ [ ./zeroCool2w.nix ];
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

      # colmena deployment configuration.
      # Usage:
      #   colmena apply                      # deploy all nodes
      #   colmena apply --on nemo            # deploy a single node
      #   colmena apply --build-on-target    # build directly on the Pi (slow but no cross-compile needed)
      colmena = {
        meta = {
          nixpkgs = import nixpkgs { system = "x86_64-linux"; };
          # Cross-compile for aarch64 Pis from your local x86 machine.
          nodeNixpkgs = {
            nemo     = import nixpkgs { system = "aarch64-linux"; };
            zerocool = import nixpkgs { system = "aarch64-linux"; };
            nintendo = import nixpkgs { system = "aarch64-linux"; };
            madison  = import nixpkgs { system = "aarch64-linux"; };
          };
        };

        bufflehead = {
          deployment = {
            targetHost = "bufflehead";
            targetUser = "root";
          };
          imports = [
            ./bufflehead.nix
            determinate.nixosModules.default
          ];
        };

        nemo = {
          deployment = {
            targetHost = "nemo";
            targetUser = "rjpc";
            keys = { };
          };
          imports = piModules ++ [
            opts
            { hostname = "nemo"; shell = "bash"; }
            ./zero2w.nix
          ];
        };

        zerocool = {
          deployment = {
            targetHost = "zerocool";
            targetUser = "rjpc";
          };
          imports = piModules ++ [ ./zeroCool2w.nix ];
        };

        nintendo = {
          deployment = {
            targetHost = "nintendo";
            targetUser = "rjpc";
          };
          imports = piModules ++ [
            opts
            { hostname = "nintendo"; shell = "zsh"; }
            ./pi3Bplus.nix
          ];
        };

        madison = {
          deployment = {
            targetHost = "madison";
            targetUser = "rjpc";
          };
          imports = piModules ++ [
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

      packages.aarch64-linux.agenix = agenix.packages.aarch64-linux.agenix;
      packages.x86_64-linux.agenix  = agenix.packages.x86_64-linux.agenix;
      packages.x86_64-linux.colmena = colmena.packages.x86_64-linux.colmena;
    };
}
