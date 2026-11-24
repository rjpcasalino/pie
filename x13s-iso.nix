{ config, lib, pkgs, ... }:

let
  inherit (config.boot.kernelPackages) kernel;
  dtbRelPath = "dtbs/qcom/sc8280xp-lenovo-thinkpad-x13s.dtb";
in
{
  # Standard NixOS minimal installer with ThinkPad X13s hardware support
  # (Linux 7.4-rc3 with nixos-hardware PR #1751 patchsets: EC, Suspend, TPM, Deepsleep, MST).
  isoImage.edition = "thinkpad-x13s";
  isoImage.volumeID = "NIXOS_X13S";

  # Kernel 7.4-rc3 via fast native x86_64 cross-compilation
  boot.kernelPackages = (import pkgs.path { system = "x86_64-linux"; }).pkgsCross.aarch64-multiplatform.linuxPackages_testing;

  # Enable verified PR #1751 7.4 patchsets
  hardware.x13s.patches = {
    camera.enable = false; # 6.18-only out-of-tree patch
    deepsleep.enable = true; # PCIe/USB/PHY CX vote dropping + GMU power gating in sleep
    ec.enable = true; # in-kernel EC driver: platform::kbd_backlight + lid breathing LED
    mst.enable = true; # DisplayPort Multi-Stream Transport (multi-monitor dock / daisy-chaining)
    suspend.enable = true; # PCI0 BCM interconnect keepalive across s2idle
    tpm.enable = true; # Qualcomm QSEECOM dTPM driver (/dev/tpm0)
  };

  boot.kernelParams = lib.mkAfter [
    "clk_ignore_unused"
    "pd_ignore_unused"
    "arm64.nopauth"
    "mem_sleep_default=s2idle"
  ];

  # Early boot display, storage, and input modules.
  # "msm" is conditionally excluded on kernel >= 7 to avoid early a660_sqe.fw
  # load failures before rootfs is mounted; UEFI simpledrm holds the console.
  boot.initrd.kernelModules = lib.mkAfter ([
    "nvme"
    "phy-qcom-qmp-pcie"
    "gpucc-sc8280xp"
    "dispcc-sc8280xp"
    "phy-qcom-edp"
    "panel-edp"
    "pwm_bl"
    "leds-qcom-lpg"
    "i2c-hid"
    "i2c-hid-of"
    "i2c-qcom-geni"
  ] ++ lib.optionals (lib.versionOlder config.boot.kernelPackages.kernel.version "7") [
    "msm"
  ] ++ lib.optionals (lib.versionAtLeast config.boot.kernelPackages.kernel.version "7") [
    "pwrseq-qcom-wcn"
    "pci-pwrctrl-pwrseq"
  ]);

  # ISO installation media: disable ZFS kernel module (broken on 7.4-rc)
  boot.supportedFilesystems.zfs = lib.mkForce false;

  # Avoid 90-second boot hang waiting for measured UKI TPM policies
  systemd.tpm2.enable = false;
  boot.initrd.systemd.tpm2.enable = false;
  security.tpm2.enable = false;
  systemd.targets.tpm2.enable = false;

  # Complete Qualcomm SC8280XP + Lenovo 21BX firmware
  hardware.enableRedistributableFirmware = true;

  # When ec.enable is false (e.g. on unpatched kernels), fall back to manual DTO & i2ctransfer.
  # When ec.enable is true, the kernel EC driver handles sleep breathing and backlight natively.
  hardware.deviceTree.overlays = lib.mkIf (!config.hardware.x13s.patches.ec.enable or false) [
    {
      name = "x13s-ec-i2c8";
      dtsText = ''
        /dts-v1/;
        /plugin/;

        / {
          compatible = "lenovo,thinkpad-x13s";

          fragment@0 {
            target-path = "/soc@0/pinctrl@f100000";
            __overlay__ {
              i2c8_default: i2c8-default-state {
                pins = "gpio43", "gpio44";
                function = "qup8";
                drive-strength = <16>;
                bias-disable;
              };
            };
          };

          fragment@1 {
            target-path = "/soc@0/geniqup@ac0000/i2c@a80000";
            __overlay__ {
              status = "okay";
              clock-frequency = <400000>;
              pinctrl-names = "default";
              pinctrl-0 = <&i2c8_default>;
            };
          };
        };
      '';
    }
  ];

  # Breathing red dot on sleep / solid on wake fallback
  powerManagement = {
    enable = true;
    powerDownCommands = lib.mkIf (!config.hardware.x13s.patches.ec.enable or false) ''
      BUS=$(basename $(ls -d /sys/devices/platform/soc@0/ac0000.geniqup/a80000.i2c/i2c-* 2>/dev/null | head -n 1) | sed "s/i2c-//")
      if [ -n "$BUS" ]; then
        ${pkgs.i2c-tools}/bin/i2ctransfer -y "$BUS" w5@0x28 0x03 0x80 0x00 0x01 0x55 || true
      fi
    '';
    resumeCommands = lib.mkIf (!config.hardware.x13s.patches.ec.enable or false) ''
      BUS=$(basename $(ls -d /sys/devices/platform/soc@0/ac0000.geniqup/a80000.i2c/i2c-* 2>/dev/null | head -n 1) | sed "s/i2c-//")
      if [ -n "$BUS" ]; then
        ${pkgs.i2c-tools}/bin/i2ctransfer -y "$BUS" w5@0x28 0x03 0x80 0x00 0x01 0xAA || true
      fi
    '';
  };

  # Useful installer tools
  environment.systemPackages = with pkgs; [
    i2c-tools
    git
    parted
    efibootmgr
  ];

  networking.wireless.enable = lib.mkForce false;
  networking.networkmanager.enable = true;

  # Include DTB in ISO boot files so GRUB/systemd-boot can load it
  isoImage.contents = [
    {
      source = "${kernel}/${dtbRelPath}";
      target = "/boot/dtbs/sc8280xp-lenovo-thinkpad-x13s.dtb";
    }
  ];
}
