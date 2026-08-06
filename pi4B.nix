{ pkgs, ... }: {

  environment.systemPackages = with pkgs; [
    bc
    curl
    fd
    unzip
    wget
    vim
  ];

  environment.sessionVariables = {
    EDITOR = "vim";
  };

  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
  };

  programs.git = {
    enable = true;
    package = pkgs.git;
    prompt.enable = true;
  };
}
