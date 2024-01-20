{ pkgs, ... }: {

  networking = {
    interfaces."wlan0".useDHCP = true;
    hostName = "nintendo";
    wireless = {
      enable = true;
      userControlled.enable = true;
      interfaces = [ "wlan0" ];
      # FIXME
      # need to either use sops or something
      networks = {
        "XXXXX" = {
          hidden = true;
          psk = "XXXXXX";
        };
      };
    };
  };

  environment.systemPackages = with pkgs; [
    neofetch
    xscreensaver
    wget
  ];

  programs.bash.enableCompletion = true;
  # above needed for below
  programs.git = {
    enable = true;
    package = pkgs.git;
    config = {
      prompt.enable = true;
    };
  };
}
