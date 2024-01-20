{ pkgs, ... }: {

  networking = {
    interfaces."wlan0".useDHCP = true;
    wireless = {
      enable = true;
      userControlled.enable = true;
      interfaces = [ "wlan0" ];
      networks = {
        "XXXXXX" = {
          hidden = true;
          psk = "XXXXXX";
        };
      };
    };
  };

  environment.systemPackages = with pkgs; [
    neofetch
  ];
  environment.pathsToLink = [ "/share/zsh" ];

  programs.zsh.interactiveShellInit = ''
    source ${pkgs.zsh-git-prompt}/share/zsh-git-prompt/zshrc.sh
  '';
  programs.git = {
    enable = true;
    package = pkgs.git;
    prompt.enable = true;
  };
  # TODO:
  # need to hold off until I move over the eth and get IPs
  # set and locked and then I can replace the aging Pi3
  #  security.acme.acceptTerms = true;
  #  security.acme.defaults.email = "ryan@rjpc.net";
  #  services.nginx = {
  #    enable = true;
  #    recommendedProxySettings = true;
  #    recommendedTlsSettings = true;
  #
  #    commonHttpConfig = ''
  #      # Add HSTS header with preloading to HTTPS requests.
  #      # Adding this header to HTTP requests is discouraged
  #      map $scheme $hsts_header {
  #          https   "max-age=31536000; includeSubdomains; preload";
  #      }
  #      add_header Strict-Transport-Security $hsts_header;
  #
  #      # Minimize information leaked to other domains
  #      add_header 'Referrer-Policy' 'origin-when-cross-origin';
  #
  #      # (Disable/Enable) embedding as a frame
  #      add_header X-Frame-Options SAMEORIGIN always;
  #
  #      # Prevent injection of code in other mime types (XSS Attacks)
  #      add_header X-Content-Type-Options nosniff;
  #
  #      # Enable XSS protection of the browser.
  #      # May be unnecessary when CSP is configured properly (see above)
  #      add_header X-XSS-Protection "1; mode=block";
  #    '';
  #
  #    virtualHosts."blog.rjpc.net" = {
  #      enableACME = true;
  #      forceSSL = true;
  #      root = "/var/www/blog_rjpc_net";
  #      locations."/archive/2019/anniversary_2019.html".extraConfig = ''
  #        auth_basic "Anna's Area";
  #        auth_basic_user_file /etc/apache2/.htpasswd;
  #      '';
  #      locations."/archive".extraConfig = ''
  #        autoindex on;
  #        autoindex_exact_size off;
  #      '';
  #      locations."/cv".extraConfig = ''
  #        autoindex on;
  #        autoindex_exact_size off;
  #      '';
  #    };
  #    virtualHosts."www.rjpc.net" = {
  #      enableACME = true;
  #      forceSSL = true;
  #      root = "/var/www/web_rjpc_net";
  #    };
  #    virtualHosts."rjpc.net" = {
  #      enableACME = true;
  #      forceSSL = true;
  #      root = "/var/www/web_rjpc_net";
  #    };
  #  };
}
