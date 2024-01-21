{ pkgs, config, ... }: {

  users.users.rjpc.shell = if config.shell == "bash" then "${pkgs.bashInteractive}${pkgs.bashInteractive.shellPath}" else "${pkgs.zsh}${pkgs.zsh.shellPath}";
  networking.hostName = config.hostname;
  environment.systemPackages = with pkgs; [
    neofetch
    xscreensaver
    wget
  ];
}
