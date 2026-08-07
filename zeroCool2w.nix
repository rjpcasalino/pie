# ZERO COOL - fancy picture frame for Vera
{ config, pkgs, lib, ... }:

let
  cfg = config.services.feh-slideshow;

  # Inline script to extract EXIF metadata cleanly for feh's --info display
  getExifInfo = pkgs.writeShellScript "get-exif-info" ''
    img="$1"
    
    date=$(${pkgs.exiftool}/bin/exiftool -s -s -f -DateTimeOriginal "$img" | grep -v '^-$$')
    location=$(${pkgs.exiftool}/bin/exiftool -s -s -f -GPSPosition "$img" | grep -v '^-$$')
    
    echo "File: $(basename "$img")"
    [ -n "$date" ] && echo "Date: $date"
    [ -n "$location" ] && echo "GPS: $location"
  '';

  # Inline script to log the active photo to a file
  logPhoto = pkgs.writeShellScript "log-photo" ''
    img="$1"
    echo "$(date '+%Y-%m-%d %H:%M:%S') - Displaying: $img" >> /home/rjpc/feh_current_slideshow.log
  '';
in
{
  options.services.feh-slideshow = {
    enable = lib.mkOption {
      type = lib.types.bool;
      default = true; # Enabled by default for zeroCool
      description = "Enable feh picture frame slideshow service";
    };

    showMetadata = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to overlay EXIF photo metadata on the screen.";
    };
  };

  config = lib.mkIf cfg.enable {
    networking.hostName = "zerocool";

    environment.systemPackages = with pkgs; [
      fastfetch
      ncdu
      feh
      git
      exiftool
      xorg.xset
    ];

    services.getty.autologinUser = "rjpc";

    systemd.services.feh-slideshow = {
      description = "feh picture frame slideshow";
      wantedBy = [ "multi-user.target" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];

      path = with pkgs; [
        git
        openssh
        bash
        xorg.xset
        exiftool
      ];

      serviceConfig = {
        User = "rjpc";
        Environment = "DISPLAY=:0";

        ExecStartPre = [
          "${pkgs.xorg.xset}/bin/xset s off"
          "${pkgs.xorg.xset}/bin/xset -dpms"
          "${pkgs.xorg.xset}/bin/xset s noblank"
          "${pkgs.bash}/bin/bash -c 'if [ -d /home/rjpc/VERA_PHOTOS/.git ]; then git -C /home/rjpc/VERA_PHOTOS pull; else git clone ssh://rjpc@192.168.12.58/~/vera-photos.git /home/rjpc/VERA_PHOTOS; fi'"
        ];

        ExecStart = ''
          ${pkgs.feh}/bin/feh \
            --fullscreen \
            --zoom \
            --quiet \
            --hide-pointer \
            --randomize \
            -D 4 \
            ${lib.optionalString cfg.showMetadata "--info \"${getExifInfo} %%F\""} \
            --action "${logPhoto} %%F" \
            /home/rjpc/VERA_PHOTOS
        '';
        Restart = "on-failure";
      };
    };
  };
}
