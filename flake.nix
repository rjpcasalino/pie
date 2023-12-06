{
  description = "Flake for building a Raspberry Pi Zero 2 SD images";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs/nixos-unstable";
    deploy-rs.url = "github:serokell/deploy-rs";
  };

  outputs = {
    self,
    nixpkgs,
    deploy-rs,
  }: rec {
    nixosConfigurations = {
      zero2w = nixpkgs.lib.nixosSystem {
        modules = [
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
          ./zero2w.nix
        ];
      };
      zeroCool2w = nixpkgs.lib.nixosSystem {
        modules = [
          "${nixpkgs}/nixos/modules/installer/sd-card/sd-image-aarch64.nix"
          ./zeroCool2w.nix
        ];
      };
    };

    deploy = {
      user = "root";
      nodes = {
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
        pi3 = {
          hostname = "nintendo";
          profiles.system.path =
            deploy-rs.lib.aarch64-linux.activate.nixos self.nixosConfigurations.pi3;
        };
      };
    };
  };
}
