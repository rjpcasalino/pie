{ config, pkgs, lib, ... }:

{
  imports = [
    ./bh-hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "bufflehead";
  networking.wireless = {
    enable = true;
    userControlled = true;
    iwd.enable = false;
    scanOnLowSignal = true;
    secretsFile = "/etc/wpa_supplicant/wireless.env";
    networks = {
      "12AngryPeople" = {
        pskRaw = "ext:PSK";
      };
    };
  };

  networking.useDHCP = false;
  networking.interfaces.eno1.useDHCP = true;
  networking.interfaces.wlp0s20f3.useDHCP = true;
  networking.nameservers = [ "192.168.12.80" ];
  networking.enableIPv6 = true;
  networking.firewall.allowedTCPPorts = [ 80 443 2283 8085 ];
  networking.firewall.enable = true;
  security.pki.certificateFiles = [ ./certs/rock-ca.crt ];
  services.gpm.enable = false;

  i18n.defaultLocale = "en_US.UTF-8";

  console = {
    earlySetup = true;
    font = "${pkgs.terminus_font}/share/consolefonts/ter-v18n.psf.gz";
    packages = with pkgs; [ terminus_font ];
    keyMap = "us";
  };

  fonts.packages = with pkgs; [
    noto-fonts
  ];

  time.timeZone = "America/Los_Angeles";

  nixpkgs.hostPlatform = "x86_64-linux";
  nixpkgs.overlays = [
    (self: super: {
      mpv-unwrapped = super.mpv-unwrapped.override {
        libbluray = super.libbluray.override {
          withAACS = true;
          withBDplus = true;
        };
      };
    })
  ];
  nixpkgs.config.packageOverrides = pkgs: {
    vaapiIntel = pkgs.intel-vaapi-driver.override { enableHybridCodec = true; };
  };
  nixpkgs.config.allowUnfree = true;

  nix = {
    settings = {
      auto-optimise-store = true;
      trusted-users = [ "@wheel" ];
    };
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # LIBVA_DRIVER_NAME=iHD
      vaapiIntel # LIBVA_DRIVER_NAME=i965 (older but works better for Firefox/Chromium)
      libva-vdpau-driver
      libvdpau-va-gl
    ];
  };

  hardware.bluetooth = {
    enable = false;
    powerOnBoot = true;
    settings = {
      General = {
        Name = "Bufflehead";
        ControllerMode = "dual";
        FastConnectable = "true";
        Experimental = "true";
      };
      Policy = { AutoEnable = "true"; };
      LE = { EnableAdvMonInterleaveScan = "true"; };
    };
  };

  hardware.enableAllFirmware = true;
  hardware.enableRedistributableFirmware = true;

  services.xserver = {
    enable = true;
    xkb.layout = "us";
    autorun = false;
    exportConfiguration = true;
    displayManager.startx.enable = true;
    windowManager.cwm.enable = true;
    videoDrivers = [ "modesetting" ];
  };

  ## MINIDLNA
  services.minidlna = {
    enable = true;
    openFirewall = true;
    settings.media_dir = [ "/mnt/sdc1" "/mnt/sdd1" "/mnt/sdb1" "/mnt/wdblack" ];
    settings.inotify = "yes";
  };
  systemd.services.minidlna = {
    after = [ "mnt-sdb1.mount" "mnt-sdc1.mount" "mnt-sdd1.mount" "mnt-wdblack.mount" ];
    wants = [ "mnt-sdb1.mount" "mnt-sdc1.mount" "mnt-sdd1.mount" "mnt-wdblack.mount" ];
  };

  ## KIWIX OFFLINE KNOWLEDGE SERVER
  services.kiwix-serve = {
    enable = true;
    port = 8085;
    openFirewall = true;
    libraryPath = "/mnt/wdblack/kiwix/library.xml";
    extraArgs = [ "-M" ];
  };
  systemd.services.kiwix-serve = {
    after = [ "mnt-wdblack.mount" ];
    wants = [ "mnt-wdblack.mount" ];
  };

  ## IMMICH PHOTO MANAGEMENT SERVER
  services.immich = {
    enable = true;
    host = "127.0.0.1";
    port = 2283;
    mediaLocation = "/mnt/wdblack/immich";
    openFirewall = true;
    machine-learning.enable = true;
  };
  systemd.services.immich-server = {
    after = [ "mnt-wdblack.mount" ];
    wants = [ "mnt-wdblack.mount" ];
  };

  ## CADDY SECURE REVERSE PROXY (:443)
  services.caddy = {
    enable = true;
    extraConfig = ''
      kiwix.home.arpa {
        tls /etc/ssl/ca/wildcard.fullchain.crt /etc/ssl/ca/wildcard.key
        reverse_proxy localhost:8085
      }

      photos.home.arpa, immich.home.arpa {
        tls /etc/ssl/ca/wildcard.fullchain.crt /etc/ssl/ca/wildcard.key
        reverse_proxy localhost:2283
      }
    '';
  };
  ##
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
    };
  };

  users.users.rjpc = {
    isNormalUser = true;
    extraGroups = [
      "adbusers"
      "audio"
      "cdrom"
      "lp"
      "lxd"
      "sound"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJNo24kFmOht87GEejqv4uWquucROWu4Fw8v8JaElomJ rjpc@zits" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDRD43YeRHIv/H4S8Hj9bw0uoGRo0W9mCMMOZvtHPBLi rjpc@air" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMM2gabh4hExixOKrLfrG029dA5TiKyr4SZB5BsJB65o rjpc@YF21" ];
    packages = with pkgs; [ ];
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  environment.systemPackages = with pkgs; [
    vim
    wget
    mpv-unwrapped
    nixpkgs-fmt
    fastfetch
    kiwix-tools
  ];

  system.stateVersion = "22.11"; # Did you read the comment? Yes.
}
