{ pkgs, ... }: {

  environment.systemPackages = with pkgs; [
    neofetch
    xscreensaver
    wget
  ];
}
