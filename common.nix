{ lib, modulesPath, pkgs, config, ... }: {
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

  # Age-encrypted WiFi credentials.
  # To create/re-encrypt: nix run .#agenix -- -e secrets/wireless.env.age
  # The plaintext file must contain:
  #   SSID=YourNetworkName
  #   PSK=YourWifiPassword
  age.secrets.wireless-env = {
    file = ./secrets/wireless.env.age;
    owner = "root";
    group = "root";
    mode = "0400";
  };

  services.openssh = {
    enable = true;
    settings = {
      # Only allow key-based authentication — no passwords, no root login
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
    };
  };

  # NTP time sync.
  services.timesyncd.enable = true;

  users.users.rjpc = {
    isNormalUser = true;
    home = "/home/rjpc";
    # FIXME:
    # shell is set in pi file
    description = "Ryan J.P. Casalino";
    hashedPassword = "$y$j9T$sGr6gwgrau81kZnyzeqFq1$vzXrHa208anPwSWdR40fZ49l7Keb9A.i1Mw.sDM5rA6";
    extraGroups = [ "wheel" "networkmanager" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJNo24kFmOht87GEejqv4uWquucROWu4Fw8v8JaElomJ rjpc@zits"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDRD43YeRHIv/H4S8Hj9bw0uoGRo0W9mCMMOZvtHPBLi rjpc@air"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMM2gabh4hExixOKrLfrG029dA5TiKyr4SZB5BsJB65o rjpc@YF21"
    ];
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };
  services.getty.autologinUser = "rjpc";

  networking = {
    interfaces."wlan0".useDHCP = true;
    wireless = {
      # The encrypted env file is decrypted at activation time by agenix.
      # To update credentials: nix run .#agenix -- -e secrets/wireless.env.age
      environmentFile = config.age.secrets.wireless-env.path;
      enable = true;
      userControlled.enable = true;
      interfaces = [ "wlan0" ];
      networks = {
        "@SSID@" = {
          hidden = true;
          psk = "@PSK@";
        };
      };
    };
    firewall.allowedTCPPorts = [ 80 443 ];
    # TFTP
    firewall.allowedUDPPortRanges = [
      {
        from = 69;
        to = 150;
      }
    ];
  };
}
