{ pkgs, config, ... }: {

  networking.hostName = config.hostname;

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
