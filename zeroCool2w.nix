# ZERO COOL - fancy picture frame for Vera
{ pkgs, ... }: {

  networking.hostName = "zerocool";

  environment.systemPackages = with pkgs; [
    feh
  ];

  # Auto-start feh slideshow on login
  # Place images in ~/Pictures; connect wifi first with:
  #   nmcli device wifi connect <SSID> password <PSK>
  services.getty.autologinUser = "rjpc";

  systemd.services.feh-slideshow = {
    description = "feh picture frame slideshow";
    wantedBy = [ "multi-user.target" ];
    after = [ "network.target" ];
    serviceConfig = {
      User = "rjpc";
      Environment = "DISPLAY=:0";
      ExecStart = "${pkgs.feh}/bin/feh --randomize --recursive --slideshow-delay 30 --fullscreen /home/rjpc/Pictures";
      Restart = "on-failure";
    };
  };
}
