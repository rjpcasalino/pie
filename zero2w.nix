{ pkgs, config, lib, ... }: {

  users.users.rjpc.shell = lib.mkMerge [(lib.mkIf (config.shell == "bash") "${pkgs.bashInteractive}${pkgs.bashInteractive.shellPath}") (lib.mkIf (config.shell == "zsh") "${pkgs.zsh}${pkgs.zsh.shellPath}")];
  networking.hostName = config.hostname;
  environment.systemPackages = with pkgs; [
    neofetch
    xscreensaver
    wget
  ];
}
