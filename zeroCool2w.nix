# ZERO COOL - fancy picture frame for Vera
{ pkgs , ... }: {

  networking = {
    interfaces."wlan0".useDHCP = true;
    hostName = "zerocool";
    wireless = {
      enable = true;
      userControlled.enable = true;
      interfaces = [ "wlan0" ];
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
    feh
  ];
}
