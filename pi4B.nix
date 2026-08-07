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


  # JENKINS CONFIGURATION
  
  # Expose Jenkins on the local network
  networking.firewall.allowedTCPPorts = [ 8080 ]; 

  services.jenkins = {
    enable = true;
    listenAddress = "0.0.0.0"; # Ensure it listens on all network interfaces
  };
}
