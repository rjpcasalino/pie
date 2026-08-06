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
      url = "github:nix-community/home-manager/release-24.05";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    determinate = {
      url = "https://flakehub.com/f/DeterminateSystems/determinate/0.1";
    };
  };

  outputs =
    { self
    , determinate
    , nixpkgs
    , home-manager
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
    };
}
