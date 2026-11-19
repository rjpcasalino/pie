{ config, lib, pkgs, ... }:

{
  imports = [
    ./arty-hardware-configuration.nix
  ];

  # 1. Systemd Boot & Qualcomm ThinkPad X13s Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Use 6.18 LTS kernel — 7.3.4 has a QMP combo PHY / s2idle regression on SC8280XP
  boot.kernelPackages = pkgs.linuxPackages_6_18;

  boot.loader.systemd-boot.extraFiles = {
    "dtbs/x13s-${config.boot.kernelPackages.kernel.version}.dtb" =
      "${config.boot.kernelPackages.kernel}/dtbs/qcom/sc8280xp-lenovo-thinkpad-x13s.dtb";
  };

  # 2. Kernel Parameters & Sleep/Power Fixes (Johan Hovold & nixos-hardware)
  boot.kernelParams = [
    "dtb=dtbs/x13s-${config.boot.kernelPackages.kernel.version}.dtb"
    "clk_ignore_unused"
    "pd_ignore_unused"
    "arm64.nopauth"
  ];

  # 3. Early Boot (initrd) Modules: NVMe, PCIe, Display, and Input
  boot.initrd.kernelModules = [
    # Storage & PCIe
    "nvme"
    "phy-qcom-qmp-pcie"

    # Display & Backlight
    "gpucc-sc8280xp"
    "dispcc-sc8280xp"
    "phy-qcom-edp"
    "panel-edp"
    "msm"
    "pwm_bl"
    "leds-qcom-lpg"

    # Input (Keyboard & Trackpad)
    "i2c-hid"
    "i2c-hid-of"
    "i2c-qcom-geni"
  ];

  # Disable TPM2 waiting (Qualcomm fTPM not exposed to mainline Linux)
  systemd.tpm2.enable = false;
  boot.initrd.systemd.tpm2.enable = false;
  security.tpm2.enable = false;
  systemd.targets.tpm2.enable = false;

  # Include Qualcomm/Lenovo 21BX proprietary firmware and Adreno GPU firmware
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [
    (pkgs.runCommand "x13s-firmware" {} ''
      mkdir -p $out/lib/firmware
      if [ -d ${./firmware} ]; then
        cp -rL ${./firmware}/* $out/lib/firmware/
      elif [ -d /etc/nixos/firmware ]; then
        cp -rL /etc/nixos/firmware/* $out/lib/firmware/
      fi
    '')
  ];
  boot.initrd.extraFirmwarePaths = [
    "qcom"
  ];

  # 4. Factory Hardware MACs & Camera DMA Rules
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", KERNELS=="0006:01:00.0", RUN+="${pkgs.iproute2}/bin/ip link set dev $name address 8c:fd:f0:98:e1:f6"
    ACTION=="add", SUBSYSTEM=="dma_heap", KERNEL=="linux,cma", GROUP="video", MODE="0660"
    ACTION=="add", SUBSYSTEM=="dma_heap", KERNEL=="system", GROUP="video", MODE="0660"
  '';

  systemd.services.bluetooth-x13s-mac = {
    wantedBy = [ "multi-user.target" ];
    before = [ "bluetooth.service" ];
    requiredBy = [ "bluetooth.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.util-linux}/bin/script -q -c '${pkgs.bluez}/bin/btmgmt --index 0 public-addr 8c:fd:f0:98:e1:f7'";
    };
  };

  # 5. Networking & Host Identity
  networking.hostName = "arty";
  networking.networkmanager.enable = true;
  networking.nameservers = [ "192.168.12.80" "1.1.1.3" ];

  # 6. Power & Battery Optimization
  powerManagement.enable = true;
  services.power-profiles-daemon.enable = true;

  # Blacklist unprovisioned Foxconn 5G WWAN modem drivers to prevent power surges/drain
  boot.blacklistedKernelModules = [
    "mhi_pci_generic"
    "mhi_wwan_mbim"
    "mhi_wwan_ctrl"
  ];
  systemd.services.ModemManager.enable = false;

  # 7. Biometrics & Fingerprint Reader (Synaptics Prometheus 06cb:00fc)
  services.fprintd.enable = true;
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if ((action.id.indexOf("net.reactivated.fprint.") === 0 ||
           action.id.indexOf("org.gnome.controlcenter.user-accounts.") === 0) &&
          subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }
    });
  '';

  # 8. Desktop & Display (GNOME Wayland & Sway with Adreno HW Accel)
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  programs.sway.enable = true;

  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "rjpc";

  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  # 9. Audio & Media
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = false;
    pulse.enable = true;
  };

  # 10. User Account & Access
  users.users.root.hashedPassword = "$y$j9T$sGr6gwgrau81kZnyzeqFq1$vzXrHa208anPwSWdR40fZ49l7Keb9A.i1Mw.sDM5rA6";

  users.users.rjpc = {
    isNormalUser = true;
    home = "/home/rjpc";
    description = "Ryan J.P. Casalino";
    hashedPassword = "$y$j9T$sGr6gwgrau81kZnyzeqFq1$vzXrHa208anPwSWdR40fZ49l7Keb9A.i1Mw.sDM5rA6";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "input" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJNo24kFmOht87GEejqv4uWquucROWu4Fw8v8JaElomJ rjpc@zits"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCvODA0utimDS5vMsmJ8JpcR9VWRIcb8mMPVm5MNZZkvqqnlqSIu0N98aHQJkp3rWEAYHCUWGSDYRi4qjdJ2p/llQSINrZhUwgUWukdUxOwU7Ru0bMZ7aBBoUXjgFFZLF1WlKVETW/wy3O39zb3L/MSTJIrAwwI3trNcqln3EEOix7cyfZteL8FbdTtus0vVAyi5iiqOcx9gv+jGAagxhd7Yh0pWo0a6MZb0sDDbHN8tXC21RFYBKa6IMmJQ505gx0N76bSb6xmSSaH1nb2khttBkT8sdu57uagnE4foDz00hSuBpOrIgawPMTyuyX2hvuDfchHet+/XBzOXH4eudHw92AE2m99cFHgrQuE9aMXN4a/iM3g/3ig1kU86GKaVWg1llzJ3oTjEBNzLXAb2zt9ZBAmkCwd+EF+n35mqD0UiIclyuTgZzUbmF7LCM/tUDaFOSl6PbY0tW6FcN26aFsWEgreTZ6edALKNO/bG7jlCxA+MxAoYgUbdp2Aa5Ywcu76nBECesvQRFaw4khF/+Lj39izA1pwenWM7fVSbX5DF3S0XwTA2OZINIxcVnE48+vup2NH8Oy27Kkc5j7MnlmueRUb9ptvUqk+vTZ49qnxipabp729q+fojoAENUz0xeQugDwVXPBBXTJGg29DYdsUYOxbIvkgY0QQmcKF6snaOw== rjpc@x13s"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDRD43YeRHIv/H4S8Hj9bw0uoGRo0W9mCMMOZvtHPBLi rjpc@air"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMM2gabh4hExixOKrLfrG029dA5TiKyr4SZB5BsJB65o rjpc@YF21"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
  };

  # 11. Essential Packages & Utilities
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
    pciutils
    usbutils
    ethtool
    iw
    wirelesstools
    networkmanager
    bluez
    pulseaudio
    fprintd
  ];

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "rjpc" ];
  };

  system.stateVersion = "24.11";
}
