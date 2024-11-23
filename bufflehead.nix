{ config, pkgs, lib, ... }:
let
  cfgShell = config.shell;
  bash = "${pkgs.bashInteractive}${pkgs.bashInteractive.shellPath}";
  zsh = "${pkgs.zsh}${pkgs.zsh.shellPath}";
in
{
  imports = [
    ./bh-hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = config.hostname;
  networking.wireless = {
    enable = true;
    environmentFile = /. + "home/rjpc/secrets/wireless.env";
    userControlled.enable = true;
    iwd.enable = false;
    scanOnLowSignal = false;
    networks = {
      "@SSID@" = {
        psk =
          "@PSK@";
      };
    };
  };

  networking.useDHCP = false;
  networking.interfaces.eno1.useDHCP = false;
  networking.interfaces.wlp0s20f3.useDHCP = true;
  networking.nameservers = [ "192.168.0.149" ];
  networking.enableIPv6 = true;
  # what is 51413
  networking.firewall.allowedTCPPorts = [ ];
  networking.firewall.enable = true;
  services.gpm.enable = true;

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
    vaapiIntel = pkgs.vaapiIntel.override { enableHybridCodec = true; };
  };
  nixpkgs.config.allowUnfree = true;

  nix = {
    package = pkgs.nixUnstable;
    settings = {
      auto-optimise-store = true;
      trusted-users = [ "@wheel" ];
    };
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  hardware.opengl = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # LIBVA_DRIVER_NAME=iHD
      vaapiIntel # LIBVA_DRIVER_NAME=i965 (older but works better for Firefox/Chromium)
      vaapiVdpau
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
    layout = "us";
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
    settings.media_dir = [ "/mnt/sdb1" "/mnt/sdc1" "/mnt/sdd1" ];
    settings.inotify = "yes";
  };
  ##
  services.openssh.enable = true;

  sound.enable = true;
  hardware.pulseaudio.enable = true;

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
    shell = lib.mkMerge [ (lib.mkIf (cfgShell == "bash") bash) (lib.mkIf (cfgShell == "zsh") zsh) ];
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
    neofetch
  ];

  system.stateVersion = "22.11"; # Did you read the comment? Yes.
}
