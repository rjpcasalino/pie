# Building a NixOS SD image for a Raspberry Pi (Zero 2 w, 3, 3B+, 4)

Based off of: https://github.com/plmercereau/nixos-pi-zero-2
Many, many thanks, plmercereau!

<hr>

1. Update `<pi>.nix`

In particular, don't forget:
- to configure your wifi
- to add an admin user able to connect through ssh / password

2. Build the image
```sh
nix build -L .#nixosConfigurations.zero2w.config.system.build.sdImage
```

3. Copy the image in your sd card

```sh
sudo rpi-imager
# or use dd
DEVICE=/dev/<disk>
sudo dd if=result/sd-image/<pi>.img of=$DEVICE bs=1M conv=fsync status=progress
```

4. Boot your Pi
5. Get your IP

```sh
ifconfig wlan0
```

6. From another machine, rebuild the system:
```sh
PI_IP=<the-pi-ip>
SSH_USER=<the-admin-user-in-the-pi>
nix run github:serokell/deploy-rs .#zero2w -- --ssh-user $SSH_USER --hostname $ZERO2_IP
```

## Notes

- The Zero 2 doesn't have enough RAM to build itself. An initial lead was to create a swap partition, but it turns out it was a bad idea, as it would have decreased the sd card lifetime (sd cards don't like many write operations). A `zram` swap is not big enough to work. Hence the use of `deploy-rs`.
  - Note that `nixos-rebuild --target-host` would work instead of using `deploy-rs`. but as `nixos-rebuild` is not available on Darwin, using `deploy-rs` that works both on NixOS and Darwin.
- `boot.kernelPackages = pkgs.linuxKernel.packages.linux_rpi3` is not working...
- the `sdImage.extraFirmwareConfig` option is not ideal as it cannot update `config.txt` after it is created in the sd image.

## See also
- [this issue](https://github.com/NixOS/nixpkgs/issues/216886)
