{ lib
, modulesPath
, pkgs
, ...
}: {
  imports = [
    ./sd-image.nix
  ];

  nixpkgs.hostPlatform = "aarch64-linux";
  nix.settings.trusted-users = [ "@wheel" ];
  system.stateVersion = "24.05";

  zramSwap = {
    enable = true;
    algorithm = "zstd";
  };

  sdImage = {
    # bzip2 compression takes loads of time with emulation, skip it. Enable this if you're low on space.
    compressImage = false;
    # TODO:
    # allow any name
    imageName = "pie.img";

    extraFirmwareConfig = {
      # Give up VRAM for more Free System Memory
      # - Disable camera which automatically reserves 128MB VRAM
      start_x = 0;
      # TODO:
      # check specs on pi4 and pi3Plus
      # - Reduce allocation of VRAM to 16MB minimum for non-rotated (32MB for rotated)
      gpu_mem = 64;
      # read the above! Zeroes need 16

      # Configure display to 800x600 so it fits on most screens
      # * See: https://elinux.org/RPi_Configuration
      # this is for zeroes
      # hdmi_group = 2;
      # hdmi_mode = 8;
    };
  };

  # Keep this to make sure wifi works
  hardware.enableRedistributableFirmware = lib.mkForce false;
  hardware.firmware = [ pkgs.raspberrypiWirelessFirmware ];

  boot = {
    # FIXME:
    # doesn't work...
    # kernelPackages = pkgs.linuxPackages_rpi3;
    initrd.availableKernelModules = [ "xhci_pci" "usbhid" "usb_storage" ];
    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };
  };

  services.sshd.enable = true;
  # NTP time sync.
  services.timesyncd.enable = true;
  services.xserver = {
    enable = true;
    layout = "us";
    autorun = true;
    exportConfiguration = true;
    desktopManager.xfce.enable = false;
    displayManager.startx.enable = false;
    displayManager.autoLogin.enable = true;
    displayManager.autoLogin.user = "rjpc";
    displayManager.lightdm = {
      enable = true;
      background = pkgs.nixos-artwork.wallpapers.nineish-dark-gray.gnomeFilePath;
      greeters.gtk.indicators = [
        "~host"
        "~spacer"
        "~clock"
        "~spacer"
        "~session"
        "~power"
      ];
      greeters.gtk.clock-format = "%A %F %I:%M %p";
    };
    windowManager.cwm.enable = true;
  };

  users.users.rjpc = {
    isNormalUser = true;
    home = "/home/rjpc";
    shell = "${pkgs.zsh}${pkgs.zsh.shellPath}";
    description = "Ryan J.P. Casalino";
    hashedPassword = "$y$j9T$sGr6gwgrau81kZnyzeqFq1$vzXrHa208anPwSWdR40fZ49l7Keb9A.i1Mw.sDM5rA6";
    extraGroups = [ "wheel" "networkmanager" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJNo24kFmOht87GEejqv4uWquucROWu4Fw8v8JaElomJ rjpc@zits" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDRD43YeRHIv/H4S8Hj9bw0uoGRo0W9mCMMOZvtHPBLi rjpc@air" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMM2gabh4hExixOKrLfrG029dA5TiKyr4SZB5BsJB65o rjpc@YF21" ];
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };
  services.getty.autologinUser = "rjpc";
}
