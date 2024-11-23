{ pkgs, config, lib, ... }:
let
  cfgShell = config.shell;
  bash = "${pkgs.bashInteractive}${pkgs.bashInteractive.shellPath}";
  zsh = "${pkgs.zsh}${pkgs.zsh.shellPath}";
in
{
  users.users.rjpc.shell = lib.mkMerge [ (lib.mkIf (cfgShell == "bash") bash) (lib.mkIf (cfgShell == "zsh") zsh) ];
  networking.hostName = config.hostname;
  environment.systemPackages = with pkgs; [
    busybox
    neofetch
    static-web-server
  ];
  services.atftpd.enable = true;
}
