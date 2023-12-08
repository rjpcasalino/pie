{ pkgs, ... }: {  
networking = {
    interfaces."wlan0".useDHCP = true;
    wireless = {
      enable = true;
      userControlled.enable = true;
      interfaces = [ "wlan0" ];
      networks = {
        "XXXXX" = {
          hidden = true;
          psk = "XXXXX";
        };
      };
    };
  };

  environment.systemPackages = with pkgs; [
    neofetch
    osv-scanner
    go
    vim
  ];

  services.sshd.enable = true;
  # TODO: move to common
  # NTP time sync.
  services.timesyncd.enable = true;
  services.xserver = {
    enable = true;
    layout = "us";
    autorun = true;
    exportConfiguration = true;
    displayManager.startx.enable = false;
    displayManager.autoLogin.enable = false;
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
    description = "Ryan J.P. Casalino";
    password = "guess";
    extraGroups = [ "wheel" "networkmanager" ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJNo24kFmOht87GEejqv4uWquucROWu4Fw8v8JaElomJ rjpc@zits" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDRD43YeRHIv/H4S8Hj9bw0uoGRo0W9mCMMOZvtHPBLi rjpc@air" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMM2gabh4hExixOKrLfrG029dA5TiKyr4SZB5BsJB65o rjpc@YF21" ];
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  services.getty.autologinUser = "rjpc";
}
