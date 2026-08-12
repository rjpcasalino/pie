{ pkgs, lib, ... }:

let
  # Simple script to swap Pluto TV channels in Chromium with Audio Flags
  launch-pluto = pkgs.writeShellScriptBin "launch-pluto" ''
    # Terminate existing browser instance cleanly
    ${pkgs.psmisc}/bin/killall -q chromium-browser || true
    ${pkgs.psmisc}/bin/killall -q chromium || true
    
    # Open Chromium with audio output & autoplay enabled
    ${pkgs.chromium}/bin/chromium \
      --kiosk \
      --no-first-run \
      --disable-session-crashed-bubble \
      --disable-infobars \
      --touch-events=enabled \
      --autoplay-policy=no-user-gesture-required \
      --enable-features=UseOzonePlatform \
      --ozone-platform=wayland \
      --alsa-output-device=default \
      "https://pluto.tv/us/live-tv/" &
  '';
in
{
  # Disable X11 / LightDM defaults inherited from common.nix
  services.xserver.enable = lib.mkForce false;
  services.xserver.displayManager.lightdm.enable = lib.mkForce false;
  services.xserver.windowManager.cwm.enable = lib.mkForce false;

  # Enable sound with PipeWire
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  environment.systemPackages = with pkgs; [
    bc
    curl
    fd
    unzip
    wget
    vim
    fastfetch
    iw
    wirelesstools
    vnstat
    iperf3
    nmap
    iproute2
    nettools
    iputils

    # Kiosk, Audio Control & Touch UI
    chromium
    foot
    sway
    psmisc
    pulsemixer # Terminal audio mixer to adjust volume/outputs if needed
    wireplumber # PipeWire session manager
    launch-pluto
  ];

  environment.sessionVariables = {
    EDITOR = "vim";
  };

  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    interactiveShellInit = ''
      bindkey -v
      if [[ "$TERM" == "xterm"* ]] || [[ "$TERM" == "foot" ]]; then
        bindkey "^?" backward-delete-char
      fi
    '';
  };

  programs.git = {
    enable = true;
    package = pkgs.git;
    prompt.enable = true;
  };

  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
  };

  # Minimal Sway Config
  environment.etc."sway/config".text = ''

    output * bg #000000 solid_color
    set $mod Mod4

    # Hotkeys to switch Pluto TV channels
    bindsym $mod+1 exec ${launch-pluto}/bin/launch-pluto 1
    bindsym $mod+2 exec ${launch-pluto}/bin/launch-pluto 2
    bindsym $mod+3 exec ${launch-pluto}/bin/launch-pluto 3
    bindsym $mod+4 exec ${launch-pluto}/bin/launch-pluto 4

    # Debugging / Shell Shortcuts
    bindsym $mod+Return exec ${pkgs.foot}/bin/foot
    bindsym $mod+q exec ${pkgs.psmisc}/bin/killall chromium
    bindsym $mod+Shift+e exec swaymsg exit

    for_window [app_id="chromium-browser"] fullscreen enable, border none
    for_window [class="Chromium-browser"] fullscreen enable, border none
    for_window [app_id="foot"] floating enable, resize set 800 500, move position center
    # Auto-start Pluto TV on boot straight from Sway
    exec ${launch-pluto}/bin/launch-pluto 1
  '';

  # Direct Autologin into Sway via greetd
  services.greetd = {
    enable = true;
    settings = {
      default_session = {
        command = "${pkgs.sway}/bin/sway -c /etc/sway/config";
        user = "rjpc";
      };
    };
  };

  services.libinput.enable = true;

  networking.firewall.allowedTCPPorts = [ 80 443 ];

  services.nginx = {
    enable = true;
    recommendedProxySettings = true;
    virtualHosts."_" = {
      default = true;
      locations."/" = {
        proxyPass = "http://127.0.0.1:8080";
      };
    };
  };
}
