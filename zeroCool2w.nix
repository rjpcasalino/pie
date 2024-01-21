# ZERO COOL - fancy picture frame for Vera
{ pkgs , ... }: {

  environment.systemPackages = with pkgs; [
    neofetch
    feh
  ];
}
