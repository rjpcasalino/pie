{ pkgs, ... }: {

  networking = {
    interfaces."wlan0".useDHCP = true;
    hostName = "nemo";
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
    xscreensaver
    wget
  ];
}
