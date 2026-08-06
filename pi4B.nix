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
    interactiveShellInit = ''
      source ${pkgs.zsh-git-prompt}/share/zsh-git-prompt/zshrc.sh
    '';
  };

  programs.git = {
    enable = true;
    package = pkgs.git;
    prompt.enable = true;
  };
}
