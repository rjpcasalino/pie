# pie — Homelab NixOS Flake & Image Builder

NixOS flake for building and deploying homelab systems (ThinkPad X13s, `bufflehead` storage/media server, and Raspberry Pi fleet) with **Colmena**, plus a shareable **ThinkPad X13s** NixOS installer ISO and Kiwix ZIM helper scripts.

Originally based on [plmercereau/nixos-pi-zero-2](https://github.com/plmercereau/nixos-pi-zero-2).

## Repository Setup

Enable the tracked git hooks once per clone:

```sh
git config core.hooksPath .githooks
```

The pre-commit hook automatically scrubs staged `.nix` wireless SSID/PSK values to avoid committing secrets.

## Hosts & Outputs

| Target | Arch | Role | Config |
| :--- | :--- | :--- | :--- |
| **`arty`** | `aarch64-linux` | Lenovo ThinkPad X13s (Snapdragon 8cx Gen 3 / SC8280XP) | `arty.nix` + `nixos-hardware` PR #1751 |
| **`x13s-iso`** | `aarch64-linux` | Shareable minimal NixOS installer ISO for ThinkPad X13s (Linux 6.18 LTS, SC8280XP DTB/firmware, TPM2 timeout fix, breathing red-dot sleep LED; no personal setup) | `x13s-iso.nix` |
| **`bufflehead`** | `x86_64-linux` | Storage/media server (Kiwix, OPDS, Immich, `btrfs`) | `bufflehead.nix` + Determinate Nix |
| **`zero2w`** (`nemo`) | `aarch64-linux` | Raspberry Pi Zero 2 W | `zero2w.nix` |
| **`zeroCool2w`** | `aarch64-linux` | Raspberry Pi Zero 2 W (`192.168.12.130`) | `zeroCool2w.nix` |
| **`pi3Bplus`** (`nintendo`) | `aarch64-linux` | Raspberry Pi 3B+ | `pi3Bplus.nix` |
| **`pi4B`** | `aarch64-linux` | Raspberry Pi 4B (`192.168.12.139`) | `pi4B.nix` |

## Deploying with Colmena

Deploy to a specific host or tag (`@pi`, `@laptop`, `@desktop`):

```sh
nix run .#colmena -- apply --on arty
nix run .#colmena -- apply --on bufflehead
nix run .#colmena -- apply --on @pi
```

*(Raspberry Pis are configured with `buildOnTarget = false` so builds happen on the deployer rather than on low-RAM Pi hardware.)*

## Building the ThinkPad X13s Installer ISO

Build a clean, shareable `aarch64-linux` NixOS minimal installer ISO for the Lenovo ThinkPad X13s (requires `aarch64-linux` host or `binfmt` emulation on `x86_64-linux`):

```sh
nix build .#x13s-iso
```

The resulting ISO is in `result/iso/`.

## Building Raspberry Pi SD Images

1. Update `<pi>.nix` (use `nmtui` on first login if Wi-Fi isn't pre-configured, and ensure an admin user with SSH/password is set).
2. Build the SD image:
   ```sh
   nix build -L .#nixosConfigurations.zero2w.config.system.build.sdImage
   ```
3. Flash to an SD card:
   ```sh
   DEVICE=/dev/<disk>
   sudo dd if=result/sd-image/<pi>.img of=$DEVICE bs=1M conv=fsync status=progress
   ```

## Kiwix ZIM Scripts

Helper scripts for maintaining offline documentation on `bufflehead`:
- `build-nixos-manual-zim.sh` — Builds a local NixOS manual ZIM archive.
- `build-expo-docs-zim.sh` — Builds a local Expo docs ZIM archive.
- `kiwix-sync.sh` / `kiwix-update.sh` — Syncs and updates ZIM libraries on `bufflehead`.
