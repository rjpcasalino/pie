{ config, lib, pkgs, ... }:

let
  inherit (config.boot.kernelPackages) kernel;
  dtbRelPath = "dtbs/qcom/sc8280xp-lenovo-thinkpad-x13s.dtb";
in
{
  # Standard NixOS minimal installer with ThinkPad X13s hardware support
  # + breathing ThinkPad red-dot sleep LED, without any personal/custom setup.
  isoImage.edition = "thinkpad-x13s";
  isoImage.volumeID = "NIXOS_X13S";

  # Ensure the SC8280XP DTB is present on the ISO's EFI/boot tree
  boot.kernelPackages = pkgs.linuxPackages_6_18;
  boot.kernelParams = lib.mkAfter [
    "clk_ignore_unused"
    "pd_ignore_unused"
    "arm64.nopauth"
    "mem_sleep_default=s2idle"
  ];

  # Early boot display, storage, and input modules
  boot.initrd.kernelModules = lib.mkAfter [
    "nvme"
    "phy-qcom-qmp-pcie"
    "gpucc-sc8280xp"
    "dispcc-sc8280xp"
    "phy-qcom-edp"
    "panel-edp"
    "msm"
    "pwm_bl"
    "leds-qcom-lpg"
    "i2c-hid"
    "i2c-hid-of"
    "i2c-qcom-geni"
  ];

  # Avoid 90-second boot hang waiting for fTPM
  systemd.tpm2.enable = false;
  boot.initrd.systemd.tpm2.enable = false;
  security.tpm2.enable = false;
  systemd.targets.tpm2.enable = false;

  # Complete Qualcomm SC8280XP + Lenovo 21BX firmware (in-kernel pd-mapper handles zstd)
  hardware.enableRedistributableFirmware = true;
  boot.initrd.extraFirmwarePaths = [ "qcom" ];

  # Device Tree Overlay: EC I2C8 bus for ThinkPad breathing red-dot sleep LED
  hardware.deviceTree.overlays = [
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

  # Breathing red dot on sleep / solid on wake via I2C EC (0x28 reg 0x80)
  powerManagement = {
    enable = true;
    powerDownCommands = ''
      BUS=$(basename $(ls -d /sys/devices/platform/soc@0/ac0000.geniqup/a80000.i2c/i2c-* 2>/dev/null | head -n 1) | sed "s/i2c-//")
      if [ -n "$BUS" ]; then
        ${pkgs.i2c-tools}/bin/i2ctransfer -y "$BUS" w5@0x28 0x03 0x80 0x00 0x01 0x55 || true
      fi
    '';
    resumeCommands = ''
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
