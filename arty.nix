{ config, lib, pkgs, ... }:

let
  # Habamax palette shared by the console, Sway status bar, and borders
  colors = {
    bg = "1c1c1c";
    red = "af5f5f";
    green = "5faf5f";
    yellow = "af875f";
    blue = "5f87af";
    magenta = "af87af";
    cyan = "5f8787";
    fg = "9e9e9e";
    brightBg = "767676";
  };

  statusRuntimeDeps = with pkgs; [
    gawk
    curl
    iproute2
    wireplumber
    procps
  ];

  statusScript = pkgs.writeShellScriptBin "wm-status" (''
    export PATH="${lib.makeBinPath (statusRuntimeDeps ++ (with pkgs; [ coreutils findutils gnugrep gnused systemd ]))}:$PATH"
    export WM_C_BG="#${colors.bg}"
    export WM_C_FG="#${colors.fg}"
    export WM_C_DIM="#${colors.brightBg}"
    export WM_C_BLUE="#${colors.blue}"
    export WM_C_CYAN="#${colors.cyan}"
    export WM_C_GREEN="#${colors.green}"
    export WM_C_YELLOW="#${colors.yellow}"
    export WM_C_RED="#${colors.red}"
    export WM_C_MAGENTA="#${colors.magenta}"
  '' + builtins.readFile ./status-line.sh);

  panelScript = pkgs.writeShellScriptBin "wm-panel" (''
    export PATH="${pkgs.hyprlauncher}/bin:${pkgs.dust}/bin:${pkgs.util-linux}/bin:${lib.makeBinPath (statusRuntimeDeps ++ (with pkgs; [ coreutils findutils gnugrep gnused systemd ]))}:$PATH"
    export WM_C_BG="#${colors.bg}"
    export WM_C_FG="#${colors.fg}"
    export WM_C_DIM="#${colors.brightBg}"
    export WM_C_BLUE="#${colors.blue}"
    export WM_C_CYAN="#${colors.cyan}"
    export WM_C_GREEN="#${colors.green}"
    export WM_C_YELLOW="#${colors.yellow}"
    export WM_C_RED="#${colors.red}"
    export WM_PANEL_LAUNCHER="${pkgs.hyprlauncher}/bin/hyprlauncher"
  '' + builtins.readFile ./status-panel.sh);

  swayWindowSwitcher = pkgs.writeScriptBin "sway-window-switcher" ''
    #!${pkgs.python3}/bin/python3
    import json
    import subprocess
    import sys

    def main():
        try:
            tree_raw = subprocess.check_output(['swaymsg', '-t', 'get_tree'])
            tree = json.loads(tree_raw)
        except Exception:
            sys.exit(1)

        def find_windows(node, ws_name=""):
            windows = []
            if node.get("type") == "workspace":
                ws_name = node.get("name", "")
            if node.get("name") and (node.get("app_id") or node.get("window_properties")):
                title = node.get("name", "Untitled")
                app = node.get("app_id") or node.get("window_properties", {}).get("class", "Unknown")
                con_id = node.get("id")
                windows.append(f"[{ws_name}] {app}: {title} | id={con_id}")
            for child in node.get("nodes", []) + node.get("floating_nodes", []):
                windows.extend(find_windows(child, ws_name))
            return windows

        windows = find_windows(tree)
        if not windows:
            sys.exit(0)

        input_str = "\n".join(windows)
        try:
            proc = subprocess.Popen(["${pkgs.hyprlauncher}/bin/hyprlauncher", "--dmenu"], stdin=subprocess.PIPE, stdout=subprocess.PIPE, text=True)
            selected, _ = proc.communicate(input=input_str)
            if selected and "id=" in selected:
                con_id = selected.strip().split("id=")[-1]
                subprocess.run(["swaymsg", f"[con_id={con_id}] focus"])
        except Exception:
            pass

    if __name__ == "__main__":
        main()
  '';

  yangStream = pkgs.writeScriptBin "yang-stream" ''
    #!${pkgs.python3}/bin/python3
    import sys
    import json
    import argparse
    import urllib.request

    DIM = "\033[2m"
    CYAN = "\033[36m"
    RESET = "\033[0m"
    BOLD = "\033[1m"

    def main():
        parser = argparse.ArgumentParser(description="Stream responses and thinking traces from YANG.")
        parser.add_argument("prompt", nargs="+", help="The prompt to send to the model")
        parser.add_argument("-m", "--model", default="deepseek-r1:14b", help="Model name (default: deepseek-r1:14b)")
        parser.add_argument("-H", "--host", default="http://yang.home.arpa:11434", help="Ollama host")
        parser.add_argument("-t", "--temperature", type=float, default=0.6, help="Sampling temperature")
        parser.add_argument("--no-thinking", action="store_true", help="Suppress thinking tokens")
        args = parser.parse_args()

        full_prompt = " ".join(args.prompt)
        url = f"{args.host}/api/generate"
        payload = json.dumps({
            "model": args.model,
            "prompt": full_prompt,
            "stream": True,
            "options": {"temperature": args.temperature}
        }).encode("utf-8")

        req = urllib.request.Request(url, data=payload, headers={"Content-Type": "application/json"})
        in_thinking = False
        in_response = False

        try:
            with urllib.request.urlopen(req, timeout=300) as resp:
                for line in resp:
                    if not line.strip():
                        continue
                    chunk = json.loads(line.decode("utf-8"))
                    thinking_token = chunk.get("thinking", "")
                    response_token = chunk.get("response", "")

                    if thinking_token and not args.no_thinking:
                        if not in_thinking:
                            sys.stdout.write(f"\n{BOLD}{CYAN}=== [Thinking Process] ==={RESET}\n{DIM}")
                            sys.stdout.flush()
                            in_thinking = True
                        sys.stdout.write(thinking_token)
                        sys.stdout.flush()

                    if response_token:
                        if in_thinking and not in_response:
                            sys.stdout.write(f"{RESET}\n\n{BOLD}=== [Final Response] ==={RESET}\n")
                            sys.stdout.flush()
                            in_response = True
                            in_thinking = False
                        sys.stdout.write(response_token)
                        sys.stdout.flush()

            sys.stdout.write(f"{RESET}\n")
            sys.stdout.flush()
        except Exception as e:
            sys.stderr.write(f"\n[ERROR] Connection to {url} failed: {e}\n")
            sys.exit(1)

    if __name__ == "__main__":
        main()
  '';

  yangLogs = pkgs.writeShellScriptBin "yang-logs" ''
    ssh yang "powershell -Command \"Get-Content -Path D:\ollama\ollama.log -Wait -Tail 30\""
  '';

  homelabSecrets = pkgs.writeShellScriptBin "homelab-secrets" ''
    set -euo pipefail
    SECRETS_FILE="''${HOMELAB_SECRETS_FILE:-/home/rjpc/homelab-docs/secrets.enc.yaml}"
    if [ $# -lt 1 ]; then
      echo "Usage: homelab-secrets [view|edit|get <yaml_path>]"
      exit 1
    fi
    case "$1" in
      view) ${pkgs.sops}/bin/sops -d "$SECRETS_FILE" ;;
      edit) ${pkgs.sops}/bin/sops "$SECRETS_FILE" ;;
      get)
        [ $# -ge 2 ] || { echo "Error: Missing secret path"; exit 1; }
        ${pkgs.yq-go}/bin/yq eval ".''${2}" <(${pkgs.sops}/bin/sops -d "$SECRETS_FILE")
        ;;
      *)
        echo "Usage: homelab-secrets [view|edit|get <yaml_path>]"
        exit 1
        ;;
    esac
  '';

  wallpaperChanger = pkgs.writeScriptBin "wallpaper-changer" (''
    #!${pkgs.perl}/bin/perl
  '' + builtins.readFile ./wallpaper-changer.pl);

  pushCursor = pkgs.writeShellScript "push-cursor-from-gtk" ''
    set -euo pipefail
    ini="''${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini"
    [ -r "$ini" ] || exit 0
    theme=$(sed -n 's/^gtk-cursor-theme-name *= *//p' "$ini" | head -1 | tr -d '\r"')
    [ -n "$theme" ] || exit 0
    IFS=':' read -ra xdg_dirs <<< "''${XDG_DATA_DIRS:-/usr/local/share:/usr/share}"
    search_dirs=("''${xdg_dirs[@]}" "$HOME/.local/share" "$HOME/.icons")
    found=0
    for dir in "''${search_dirs[@]}"; do
      if [ -d "$dir/icons/$theme/cursors" ]; then
        found=1
        break
      fi
    done
    [ "$found" -eq 1 ] || exit 0
    size=$(sed -n 's/^gtk-cursor-theme-size *= *//p' "$ini" | head -1 | tr -cd 0-9)
    [ -n "$size" ] || size=24
    hyprctl setcursor "$theme" "$size" || true
  '';

  resetCursor = pkgs.writeShellScript "reset-cursor-to-hyprland" ''
    set -euo pipefail
    blank=blank-theme
    for f in "''${XDG_CONFIG_HOME:-$HOME/.config}/gtk-3.0/settings.ini" \
             "''${XDG_CONFIG_HOME:-$HOME/.config}/gtk-4.0/settings.ini" \
             "$HOME/.gtkrc-2.0"; do
      mkdir -p "$(dirname "$f")"
      if [ -f "$f" ] && grep -q "^gtk-cursor-theme-name" "$f"; then
        sed -i "s|^gtk-cursor-theme-name.*|gtk-cursor-theme-name=$blank|" "$f"
      else
        printf '[Settings]\ngtk-cursor-theme-name=%s\n' "$blank" >> "$f"
      fi
    done
    mkdir -p "$HOME/.icons/$blank/cursors" "$HOME/.local/share/icons/$blank/cursors"
    hyprctl setcursor "$blank" 24 || true
  '';

  defaultWaybarConfigJson = ''
    {
      "layer": "top",
      "position": "top",
      "height": 28,
      "spacing": 4,
      "modules-left": ["hyprland/workspaces", "hyprland/window"],
      "modules-center": [
        "custom/status-net",
        "custom/status-disk",
        "custom/status-cpu",
        "custom/status-mem",
        "custom/status-vol"
      ],
      "modules-right": ["tray", "clock"],

      "hyprland/workspaces": {
        "format": "{icon}",
        "format-icons": {
          "active": "●",
          "default": "○"
        }
      },

      "hyprland/window": {
        "max-length": 60
      },

      "custom/status-net": {
        "exec": "${statusScript}/bin/wm-status --once --section net",
        "interval": 2,
        "restart-interval": 5,
        "max-length": 400,
        "on-click": "${panelScript}/bin/wm-panel --section net"
      },

      "custom/status-disk": {
        "exec": "${statusScript}/bin/wm-status --once --section disk",
        "interval": 5,
        "restart-interval": 10,
        "max-length": 120,
        "on-click": "${panelScript}/bin/wm-panel --section disk"
      },

      "custom/status-cpu": {
        "exec": "${statusScript}/bin/wm-status --once --section cpu",
        "interval": 2,
        "restart-interval": 5,
        "max-length": 80,
        "on-click": "${panelScript}/bin/wm-panel --section cpu"
      },

      "custom/status-mem": {
        "exec": "${statusScript}/bin/wm-status --once --section mem",
        "interval": 2,
        "restart-interval": 5,
        "max-length": 100,
        "on-click": "${panelScript}/bin/wm-panel --section mem"
      },

      "custom/status-vol": {
        "exec": "${statusScript}/bin/wm-status --once --section vol",
        "interval": 2,
        "restart-interval": 5,
        "max-length": 60,
        "on-click": "${panelScript}/bin/wm-panel --section vol",
        "on-click-middle": "${pkgs.wireplumber}/bin/wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle",
        "on-scroll-up": "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+",
        "on-scroll-down": "${pkgs.wireplumber}/bin/wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"
      },

      "clock": {
        "interval": 1,
        "format": "<span>{:%a %d %b %Y  %I:%M:%S %p}</span>",
        "tooltip-format": "<big>{}</big>",
        "on-click": "${panelScript}/bin/wm-panel --section time"
      },

      "tray": {
        "icon-size": 16,
        "spacing": 8
      }
    }
  '';

  defaultWaybarStyleCss = ''
    * {
      font-family: "Noto Sans", "Noto Color Emoji", "Font Awesome 6 Free";
      font-size: 13px;
      border: none;
      border-radius: 0;
      min-height: 0;
    }

    window#waybar {
      background-color: #${colors.bg};
      color: #${colors.fg};
    }

    #workspaces button {
      padding: 0 5px;
      color: #${colors.brightBg};
      min-width: 0;
    }

    #workspaces button.active {
      color: #${colors.blue};
    }

    #window {
      color: #${colors.fg};
    }

    #custom-status-net,
    #custom-status-disk,
    #custom-status-cpu,
    #custom-status-mem,
    #custom-status-vol,
    #clock {
      padding: 0 6px;
      color: #${colors.fg};
    }

    #custom-status-vol,
    #clock {
      border-radius: 4px;
    }

    #custom-status-vol:hover,
    #clock:hover {
      background-color: #${colors.brightBg};
    }

    #tray {
      padding: 0 6px;
    }
  '';
in
{
  imports = [
    ./arty-hardware-configuration.nix
  ];

  nixpkgs.config.allowUnfree = true;

  # 1. Systemd Boot & Qualcomm ThinkPad X13s Bootloader
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # Use 6.18 LTS kernel — 7.3.4 has a QMP combo PHY / s2idle regression on SC8280XP
  boot.kernelPackages = pkgs.linuxPackages_6_18;

  boot.loader.systemd-boot.extraFiles = {
    "dtbs/x13s-${config.boot.kernelPackages.kernel.version}.dtb" =
      ./dtbs/x13s-6.18.63.dtb;
  };

  # 2. Kernel Parameters & Sleep/Power Fixes (Johan Hovold & nixos-hardware)
  boot.kernelParams = [
    "dtb=dtbs/x13s-${config.boot.kernelPackages.kernel.version}.dtb"
    "clk_ignore_unused"
    "pd_ignore_unused"
    "arm64.nopauth"
  ];

  # 3. Early Boot (initrd) Modules: NVMe, PCIe, Display, and Input
  boot.initrd.kernelModules = [
    # Storage & PCIe
    "nvme"
    "phy-qcom-qmp-pcie"

    # Display & Backlight
    "gpucc-sc8280xp"
    "dispcc-sc8280xp"
    "phy-qcom-edp"
    "panel-edp"
    "msm"
    "pwm_bl"
    "leds-qcom-lpg"

    # Input (Keyboard & Trackpad)
    "i2c-hid"
    "i2c-hid-of"
    "i2c-qcom-geni"
  ];

  # Disable TPM2 waiting (Qualcomm fTPM not exposed to mainline Linux)
  systemd.tpm2.enable = false;
  boot.initrd.systemd.tpm2.enable = false;
  security.tpm2.enable = false;
  systemd.targets.tpm2.enable = false;

  # Include Qualcomm/Lenovo 21BX proprietary firmware and Adreno GPU firmware
  hardware.enableRedistributableFirmware = true;
  hardware.firmware = [
    (pkgs.runCommand "x13s-firmware" {} ''
      mkdir -p $out/lib/firmware
      if [ -d ${./firmware} ]; then
        cp -rL ${./firmware}/* $out/lib/firmware/
      elif [ -d /etc/nixos/firmware ]; then
        cp -rL /etc/nixos/firmware/* $out/lib/firmware/
      fi
    '')
  ];
  boot.initrd.extraFirmwarePaths = [
    "qcom"
  ];

  # 4. Factory Hardware MACs & Camera DMA Rules
  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="net", KERNELS=="0006:01:00.0", RUN+="${pkgs.iproute2}/bin/ip link set dev $name address 8c:fd:f0:98:e1:f6"
    ACTION=="add", SUBSYSTEM=="dma_heap", KERNEL=="linux,cma", GROUP="video", MODE="0660"
    ACTION=="add", SUBSYSTEM=="dma_heap", KERNEL=="system", GROUP="video", MODE="0660"
  '';

  systemd.services.bluetooth-x13s-mac = {
    wantedBy = [ "multi-user.target" ];
    before = [ "bluetooth.service" ];
    requiredBy = [ "bluetooth.service" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      ExecStart = "${pkgs.util-linux}/bin/script -q -c '${pkgs.bluez}/bin/btmgmt --index 0 public-addr 8c:fd:f0:98:e1:f7'";
    };
  };

  # 5. Networking, PKI & Host Identity
  networking.hostName = "arty";
  networking.networkmanager.enable = true;
  networking.nameservers = [ "192.168.12.80" "1.1.1.3" ];
  networking.extraHosts = ''
    192.168.12.80 rock.home.arpa rock
    192.168.12.58 zits.home.arpa zits
    192.168.12.69 yang.home.arpa yang
    192.168.12.122 bufflehead.home.arpa bufflehead photos.home.arpa immich.home.arpa vault.home.arpa kiwix.home.arpa
  '';
  networking.firewall.allowedUDPPortRanges = [
    # Mosh roaming UDP ports
    { from = 60000; to = 61000; }
  ];

  # Trust Rock Home Lab Root CA for green padlocks across *.home.arpa
  security.pki.certificateFiles = [ ./certs/rock-ca.crt ];

  # Timezone & Console Palette (Habamax)
  time.timeZone = "America/Los_Angeles";
  console = {
    colors = [
      "1c1c1c" "af5f5f" "5faf5f" "af875f"
      "5f87af" "af87af" "5f8787" "9e9e9e"
      "767676" "d75f87" "87d787" "d7af87"
      "5fafd7" "d787d7" "87afaf" "c7c7c7"
    ];
  };

  # 6. Power & Battery Optimization
  powerManagement = {
    enable = true;
    powerDownCommands = ''
      # Modern Standby Lowest Power State Entry: notify EC to pulse/breathe LED
      BUS=$(basename $(ls -d /sys/devices/platform/soc@0/ac0000.geniqup/a80000.i2c/i2c-* 2>/dev/null | head -n 1) | sed "s/i2c-//")
      if [ -n "$BUS" ]; then
        ${pkgs.i2c-tools}/bin/i2ctransfer -y "$BUS" w5@0x28 0x03 0x80 0x00 0x01 0x55 || true
      fi
    '';
    resumeCommands = ''
      # Modern Standby Lowest Power State Exit: notify EC to restore normal solid LED
      BUS=$(basename $(ls -d /sys/devices/platform/soc@0/ac0000.geniqup/a80000.i2c/i2c-* 2>/dev/null | head -n 1) | sed "s/i2c-//")
      if [ -n "$BUS" ]; then
        ${pkgs.i2c-tools}/bin/i2ctransfer -y "$BUS" w5@0x28 0x03 0x80 0x00 0x01 0xAA || true
      fi
    '';
  };
  services.power-profiles-daemon.enable = true;

  # Blacklist unprovisioned Foxconn 5G WWAN modem drivers to prevent power surges/drain
  boot.blacklistedKernelModules = [
    "mhi_pci_generic"
    "mhi_wwan_mbim"
    "mhi_wwan_ctrl"
  ];
  systemd.services.ModemManager.enable = false;

  # 7. Biometrics & Fingerprint Reader (Synaptics Prometheus 06cb:00fc)
  services.fprintd.enable = true;
  security.polkit.extraConfig = ''
    polkit.addRule(function(action, subject) {
      if ((action.id.indexOf("net.reactivated.fprint.") === 0 ||
           action.id.indexOf("org.gnome.controlcenter.user-accounts.") === 0) &&
          subject.isInGroup("wheel")) {
        return polkit.Result.YES;
      }
    });
  '';

  # 8. Desktop, Fonts & Display (GNOME Wayland & Sway with Adreno HW Accel)
  fonts = {
    enableDefaultPackages = true;
    packages = with pkgs; [
      noto-fonts
      noto-fonts-cjk-sans
      noto-fonts-color-emoji
      liberation_ttf
      dejavu_fonts
      font-awesome
      roboto
      jetbrains-mono
      commit-mono
    ];
  };

  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "rjpc";

  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  # Sway Window Manager (matching zits keybindings & Habamax status bar)
  programs.sway = {
    enable = true;
    wrapperFeatures.gtk = true;
    extraPackages = with pkgs; [
      foot
      swaylock
      swayidle
      swaybg
      wl-clipboard
      grim
      slurp
      mako
      qt5.qtwayland
      qt6.qtwayland
      gammastep
      brightnessctl
      pamixer
      playerctl
      hyprlauncher
      nwg-look
      statusScript
      panelScript
      swayWindowSwitcher
    ] ++ statusRuntimeDeps;
  };

  environment.etc."sway/config".text = ''
    ### Variables
    set $mod Mod4
    set $left h
    set $down j
    set $up k
    set $right l
    set $term foot
    set $menu ${pkgs.hyprlauncher}/bin/hyprlauncher -t

    ### Display & Input (ThinkPad X13s eDP-1 & TrackPoint/Touchpad)
    output eDP-1 scale 1.25
    input type:touchpad {
        tap enabled
        natural_scroll enabled
        dwt enabled
    }

    ### Night Light (Gammastep)
    exec ${pkgs.gammastep}/bin/gammastep -l 47.60:-122.33 -t 6500:3500

    ### Key bindings (zits parity)
    bindsym Control+$mod+1 move scratchpad; scratchpad show
    bindsym $mod+Shift+equal floating disable
    bindsym $mod+Shift+plus floating disable
    bindsym $mod+Return exec $term
    bindsym Control+$mod+Return exec $term -e tmux
    bindsym Control+$mod+t exec $term -e btop
    bindsym $mod+Shift+f exec $term -e yazi
    bindsym $mod+slash exec ${panelScript}/bin/wm-panel --section binds
    bindsym $mod+Shift+q kill
    bindsym $mod+d exec $menu
    bindsym $mod+space exec $menu
    floating_modifier $mod normal
    bindsym $mod+Shift+c reload
    bindsym $mod+Shift+e exec swaynag -t warning -m 'Exit sway?' -B 'Yes, exit sway' 'swaymsg exit'

    # Window & Workspace Tabbing / Cycling
    bindsym Alt+Tab focus next
    bindsym Alt+Shift+Tab focus prev
    bindsym $mod+Tab focus next
    bindsym $mod+Shift+Tab focus prev
    bindsym Control+Alt+Tab workspace next
    bindsym Control+Alt+Shift+Tab workspace prev
    bindsym Control+$mod+Tab workspace next
    bindsym Control+$mod+Shift+Tab workspace prev

    # cwm Window Management Shortcuts
    bindsym $mod+w exec ${swayWindowSwitcher}/bin/sway-window-switcher
    bindsym Mod1+w exec ${swayWindowSwitcher}/bin/sway-window-switcher
    bindsym Control+$mod+h move scratchpad
    bindsym $mod+u scratchpad show
    bindsym $mod+m fullscreen toggle
    bindsym $mod+x kill

    # Moving around
    bindsym $mod+$left focus left
    bindsym $mod+$down focus down
    bindsym $mod+$up focus up
    bindsym $mod+$right focus right
    bindsym $mod+Left focus left
    bindsym $mod+Down focus down
    bindsym $mod+Up focus up
    bindsym $mod+Right focus right

    bindsym $mod+Shift+$left move left
    bindsym $mod+Shift+$down move down
    bindsym $mod+Shift+$up move up
    bindsym $mod+Shift+$right move right
    bindsym $mod+Shift+Left move left
    bindsym $mod+Shift+Down move down
    bindsym $mod+Shift+Up move up
    bindsym $mod+Shift+Right move right

    # Workspaces
    bindsym $mod+1 workspace number 1
    bindsym $mod+2 workspace number 2
    bindsym $mod+3 workspace number 3
    bindsym $mod+4 workspace number 4
    bindsym $mod+5 workspace number 5
    bindsym $mod+6 workspace number 6
    bindsym $mod+7 workspace number 7
    bindsym $mod+8 workspace number 8
    bindsym $mod+9 workspace number 9
    bindsym $mod+0 workspace number 10

    bindsym $mod+Shift+1 move container to workspace number 1
    bindsym $mod+Shift+2 move container to workspace number 2
    bindsym $mod+Shift+3 move container to workspace number 3
    bindsym $mod+Shift+4 move container to workspace number 4
    bindsym $mod+Shift+5 move container to workspace number 5
    bindsym $mod+Shift+6 move container to workspace number 6
    bindsym $mod+Shift+7 move container to workspace number 7
    bindsym $mod+Shift+8 move container to workspace number 8
    bindsym $mod+Shift+9 move container to workspace number 9
    bindsym $mod+Shift+0 move container to workspace number 10

    # Layout
    bindsym $mod+b splith
    bindsym $mod+v splitv
    bindsym $mod+s layout stacking
    bindsym $mod+t layout tabbed
    bindsym $mod+e layout toggle split
    bindsym $mod+f fullscreen
    bindsym $mod+Shift+space floating toggle
    bindsym $mod+a focus parent

    # Scratchpad
    bindsym $mod+Shift+minus move scratchpad
    bindsym $mod+minus scratchpad show

    # Resize mode
    mode "resize" {
        bindsym $left resize shrink width 10px
        bindsym $down resize grow height 10px
        bindsym $up resize shrink height 10px
        bindsym $right resize grow width 10px
        bindsym Left resize shrink width 10px
        bindsym Down resize grow height 10px
        bindsym Up resize shrink height 10px
        bindsym Right resize grow width 10px
        bindsym Return mode "default"
        bindsym Escape mode "default"
    }
    bindsym $mod+r mode "resize"

    # Audio, Brightness & Screenshots
    bindsym $mod+Control+v exec ${panelScript}/bin/wm-panel --section vol
    bindsym --locked XF86AudioMute exec wpctl set-mute \@DEFAULT_AUDIO_SINK@ toggle
    bindsym --locked XF86AudioLowerVolume exec wpctl set-volume \@DEFAULT_AUDIO_SINK@ 5%-
    bindsym --locked XF86AudioRaiseVolume exec wpctl set-volume \@DEFAULT_AUDIO_SINK@ 5%+
    bindsym --locked XF86AudioPlay exec ${pkgs.playerctl}/bin/playerctl play-pause
    bindsym --locked XF86AudioNext exec ${pkgs.playerctl}/bin/playerctl next
    bindsym --locked XF86AudioPrev exec ${pkgs.playerctl}/bin/playerctl previous
    bindsym --locked XF86MonBrightnessDown exec ${pkgs.brightnessctl}/bin/brightnessctl set 5%-
    bindsym --locked XF86MonBrightnessUp exec ${pkgs.brightnessctl}/bin/brightnessctl set 5%+

    bindsym $mod+Shift+s exec bash -c 'FILE=~/Pictures/Screenshot_$(date +%Y%m%d_%H%M%S).png; grim -g "$(slurp)" "$FILE" && wl-copy < "$FILE"'
    bindsym Print exec bash -c 'FILE=~/Pictures/Screenshot_$(date +%Y%m%d_%H%M%S).png; grim -g "$(slurp)" "$FILE" && wl-copy < "$FILE"'

    # Idle & Lock
    exec swayidle -w \
        timeout 300 'swaylock -f -c 000000' \
        timeout 600 'swaymsg "output * dpms off"' \
        resume 'swaymsg "output * dpms on"' \
        before-sleep 'swaylock -f -c 000000'

    # Status Bar (Habamax with Battery segment)
    bar {
        position top
        status_command ${statusScript}/bin/wm-status --watch
        pango_markup enabled
        colors {
            statusline #ffffff
            background #1c1c1c
            inactive_workspace #32323200 #32323200 #5c5c5c
        }
    }
  '';

  environment.sessionVariables = {
    NIXOS_OZONE_WL = "1";
    MOZ_ENABLE_WAYLAND = "1";
    TERMINAL = "foot";
    OLLAMA_HOST = "http://yang.home.arpa:11434";
  };

  # 8b. Hyprland, Waybar, Hyprlock, Hypridle & Hyprlauncher (matching zits)
  programs.hyprland = {
    enable = true;
    xwayland.enable = true;
  };

  programs.hyprlock.enable = true;
  services.hypridle.enable = true;

  systemd.user.targets.hyprland-session = {
    description = "Services belonging to the Hyprland session";
  };

  systemd.user.services.waybar = {
    description = "Waybar status bar for the Hyprland session";
    wantedBy = [ "hyprland-session.target" ];
    path = [ pkgs.waybar ] ++ statusRuntimeDeps;
    unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
    startLimitIntervalSec = 0;
    serviceConfig = {
      ExecStart = "${pkgs.waybar}/bin/waybar -c /etc/xdg/waybar/config.jsonc -s /etc/xdg/waybar/style.css";
      Restart = "on-failure";
      RestartSec = "1s";
    };
  };

  systemd.user.services.hypridle.wantedBy = [ "hyprland-session.target" ];

  systemd.user.services.hyprlauncher = {
    description = "Hyprlauncher daemon for the Hyprland session";
    wantedBy = [ "hyprland-session.target" ];
    unitConfig.ConditionEnvironment = "WAYLAND_DISPLAY";
    startLimitIntervalSec = 0;
    environment = {
      TERMINAL = "foot";
    };
    serviceConfig = {
      Environment = lib.mkForce [
        "PATH=/run/wrappers/bin:%h/.local/share/flatpak/exports/bin:/var/lib/flatpak/exports/bin:%h/.nix-profile/bin:/nix/profile/bin:%h/.local/state/nix/profile/bin:/etc/profiles/per-user/%u/bin:/nix/var/nix/profiles/default/bin:/run/current-system/sw/bin"
        "LOCALE_ARCHIVE=${config.i18n.glibcLocales}/lib/locale/locale-archive"
        "TZDIR=/etc/zoneinfo"
        "TERMINAL=foot"
      ];
      ExecStart = "${pkgs.hyprlauncher}/bin/hyprlauncher -d";
      Restart = "on-failure";
      RestartSec = "1s";
    };
  };

  system.activationScripts.initHyprToolkit = lib.stringAfter [ "etc" ] ''
    for user_dir in /home/*; do
      if [ -d "$user_dir" ]; then
        mkdir -p "$user_dir/.config/hypr"
        ln -sf "/etc/xdg/hypr/hyprtoolkit.conf" "$user_dir/.config/hypr/hyprtoolkit.conf"
        ln -sf "/etc/xdg/hypr/hyprlauncher.conf" "$user_dir/.config/hypr/hyprlauncher.conf"
        chown -h -R "$(stat -c '%u:%g' "$user_dir")" "$user_dir/.config/hypr" || true
      fi
    done
    rm -f /etc/static/xdg/hypr/hyprland.conf /etc/xdg/hypr/hyprland.conf
  '';

  environment.etc."xdg/hypr/hyprland.lua".text = ''
    -- Hyprland configuration for ThinkPad X13s (arty)
    hl.monitor({ output = "eDP-1", mode = "preferred", position = "0x0", scale = 1.25 })
    hl.monitor({ output = "", mode = "preferred", position = "auto", scale = 1 })

    local terminal = "foot"
    local menu     = "hyprlauncher -t"
    local mainMod  = "SUPER"

    hl.env("HYPRCURSOR_SIZE", "24")
    hl.env("XCURSOR_SIZE", "24")

    hl.config({
        general = {
            gaps_in    = 4,
            gaps_out   = 8,
            border_size = 2,
            col = {
                active_border   = { colors = { "rgba(${colors.blue}ff)", "rgba(${colors.cyan}ff)" }, angle = 45 },
                inactive_border = "rgba(${colors.brightBg}aa)",
            },
            layout = "dwindle",
        },
        decoration = {
            rounding = 8,
            blur = { enabled = true, size = 3, passes = 2 },
        },
        animations = {
            enabled = true,
            animation = {
                "layers, 0",
                "fadeLayersIn, 0",
                "fadeLayersOut, 0",
                "fadePopups, 0"
            }
        },
        input = {
            touchpad = {
                natural_scroll = true,
                disable_while_typing = true,
                tap_to_click = true,
            }
        },
        misc = {
            bell_sound = "none",
        },
    })

    -- Terminal, launcher, and keybindings cheat sheet
    hl.bind(mainMod .. " + Return", hl.dsp.exec_cmd(terminal))
    hl.bind(mainMod .. " + Space",  hl.dsp.exec_cmd(menu))
    hl.bind(mainMod .. " + D",      hl.dsp.exec_cmd(menu))
    hl.bind(mainMod .. " + ALT + Space", hl.dsp.exec_cmd("hyprlauncher -f math"))
    hl.bind(mainMod .. " + slash",  hl.dsp.exec_cmd("${panelScript}/bin/wm-panel --section binds"))

    -- Focus: arrows, plus vim hjkl
    local focus_dirs = {
        { "left",  { "left", "H" } },
        { "right", { "right", "L" } },
        { "up",    { "up", "K" } },
        { "down",  { "down", "J" } },
    }
    for _, entry in ipairs(focus_dirs) do
        for _, key in ipairs(entry[2]) do
            hl.bind(mainMod .. " + " .. key, hl.dsp.focus({ direction = entry[1] }))
        end
    end

    -- Swap on SHIFT
    local swap_dirs = {
        { "left",  { "left", "H" } },
        { "right", { "right", "L" } },
        { "up",    { "K" } },
        { "down",  { "J" } },
    }
    for _, entry in ipairs(swap_dirs) do
        for _, key in ipairs(entry[2]) do
            hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.swap({ direction = entry[1] }))
        end
    end

    -- Window management
    hl.bind(mainMod .. " + W", hl.dsp.window.close())
    hl.bind(mainMod .. " + Q", hl.dsp.window.close())
    hl.bind(mainMod .. " + SHIFT + Q", hl.dsp.window.close())
    hl.bind(mainMod .. " + X", hl.dsp.window.close())
    hl.bind("CTRL + ALT + Delete", hl.dsp.exit())
    hl.bind(mainMod .. " + T", hl.dsp.window.float({ action = "toggle" }))
    hl.bind(mainMod .. " + SHIFT + Space", hl.dsp.window.float({ action = "toggle" }))
    hl.bind(mainMod .. " + O", hl.dsp.window.pin({ action = "toggle" }))

    -- Fullscreen
    hl.bind(mainMod .. " + F", hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" }))
    hl.bind(mainMod .. " + ALT + F", hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" }))
    hl.bind(mainMod .. " + CTRL + F", hl.dsp.window.fullscreen_state({ action = "set", internal = 1, client = 1 }))

    -- Layouts and grouping
    hl.bind(mainMod .. " + G", hl.dsp.group.toggle())
    hl.bind(mainMod .. " + ALT + G", hl.dsp.window.move({ out_of_group = true }))
    hl.bind(mainMod .. " + CTRL + right", hl.dsp.group.next())
    hl.bind(mainMod .. " + CTRL + left",  hl.dsp.group.prev())

    -- TUI launchers
    hl.bind(mainMod .. " + CTRL + T",      hl.dsp.exec_cmd(terminal .. " -e btop"))
    hl.bind(mainMod .. " + CTRL + Return", hl.dsp.exec_cmd(terminal .. " -e tmux"))
    hl.bind(mainMod .. " + SHIFT + F",     hl.dsp.exec_cmd(terminal .. " -e yazi"))
    hl.bind(mainMod .. " + CTRL + W",      hl.dsp.exec_cmd(terminal .. " -e nmtui"))
    hl.bind(mainMod .. " + CTRL + B",      hl.dsp.exec_cmd(terminal .. " -e bluetoothctl"))

    -- Appearance & cursor
    hl.bind(mainMod .. " + A", hl.dsp.exec_cmd("sh -c 'nwg-look; ${pushCursor}'"))
    hl.bind(mainMod .. " + C", hl.dsp.exec_cmd("${resetCursor}"))

    -- Workspaces 1..10
    for i = 1, 10 do
        local key = i % 10
        hl.bind(mainMod .. " + " .. key,         hl.dsp.focus({ workspace = i }))
        hl.bind(mainMod .. " + SHIFT + " .. key, hl.dsp.window.move({ workspace = i }))
        hl.bind(mainMod .. " + ALT + " .. key,   hl.dsp.window.move({ workspace = i, follow = false }))
    end

    -- Mouse: drag and resize
    hl.bind(mainMod .. " + mouse:272", hl.dsp.window.drag(),   { mouse = true })
    hl.bind(mainMod .. " + mouse:273", hl.dsp.window.resize(), { mouse = true })

    -- Media and brightness
    hl.bind(mainMod .. " + V",         hl.dsp.exec_cmd("${panelScript}/bin/wm-panel --section vol"))
    hl.bind("XF86AudioRaiseVolume",   hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%+"), { locked = true, repeating = true })
    hl.bind("XF86AudioLowerVolume",   hl.dsp.exec_cmd("wpctl set-volume @DEFAULT_AUDIO_SINK@ 5%-"), { locked = true, repeating = true })
    hl.bind("XF86AudioMute",          hl.dsp.exec_cmd("wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle"))
    hl.bind("XF86AudioPlay",          hl.dsp.exec_cmd("playerctl play-pause"))
    hl.bind("XF86AudioNext",          hl.dsp.exec_cmd("playerctl next"))
    hl.bind("XF86AudioPrev",          hl.dsp.exec_cmd("playerctl previous"))
    hl.bind("XF86MonBrightnessDown",  hl.dsp.exec_cmd("brightnessctl set 5%-"), { locked = true })
    hl.bind("XF86MonBrightnessUp",    hl.dsp.exec_cmd("brightnessctl set 5%+"), { locked = true })

    -- Screen lock & screenshots
    hl.bind(mainMod .. " + ALT + L", hl.dsp.exec_cmd("hyprlock"))
    local screenshot = "bash -c 'FILE=~/Pictures/Screenshot_$(date +%Y%m%d_%H%M%S).png; grim -g \"$(slurp)\" \"$FILE\" && wl-copy < \"$FILE\"'"
    hl.bind(mainMod .. " + SHIFT + S", hl.dsp.exec_cmd(screenshot))
    hl.bind("Print", hl.dsp.exec_cmd(screenshot))

    hl.window_rule({
      name = "firefox-no-animations",
      match = { class = "[Ff]irefox" },
      no_anim = true,
      opacity = "1.0 override 1.0 override 1.0 override"
    })

    hl.on("hyprland.start", function()
        hl.exec_cmd("systemctl --user import-environment WAYLAND_DISPLAY HYPRLAND_INSTANCE_SIGNATURE XDG_CURRENT_DESKTOP")
        hl.exec_cmd("systemctl --user start hyprland-session.target")
        hl.exec_cmd("gammastep -l 47.60:-122.33 -t 6500:3500")
        hl.exec_cmd("systemd-cat -t wallpaper-changer ${wallpaperChanger}/bin/wallpaper-changer")
        hl.exec_cmd("${pushCursor}")
    end)
  '';

  environment.etc."xdg/hypr/hypridle.conf".text = ''
    general {
        lock_cmd = pidof hyprlock || hyprlock
        before_sleep_cmd = loginctl lock-session
        after_sleep_cmd = hyprctl dispatch 'hl.dsp.dpms({ action = "on" })'
    }

    listener {
        timeout = 300
        on-timeout = loginctl lock-session
    }

    listener {
        timeout = 600
        on-timeout = hyprctl dispatch 'hl.dsp.dpms({ action = "off" })'
        on-resume = hyprctl dispatch 'hl.dsp.dpms({ action = "on" })'
    }
  '';

  environment.etc."xdg/hypr/hyprlock.conf".text = ''
    general {
        hide_cursor = true
        grace = 2
        no_fade_in = false
        ignore_empty_input = true
    }

    background {
        monitor =
        path =
        color = 0x${colors.bg}ff
    }

    input-field {
        monitor =
        size = 300, 46
        outline_thickness = 2
        dots_size = 0.22
        dots_spacing = 0.3
        outer_color = 0x${colors.fg}ff
        inner_color = 0x${colors.bg}ff
        font_color = 0x${colors.fg}ff
        fade_on_empty = true
        placeholder_text = <i>Password</i>
        hide_input = false
        check_color = 0x${colors.green}ff
        fail_color = 0x${colors.red}ff
        fail_text = <i>$FAIL ($ATTEMPTS)</i>
        capslock_color = 0x${colors.yellow}ff
        rounding = 8
        position = 0, -120
        halign = center
        valign = center
    }

    label {
        monitor =
        text = $TIME
        color = 0x${colors.fg}ff
        font_size = 76
        font_family = Noto Sans
        position = 0, 200
        halign = center
        valign = center
    }
  '';

  environment.etc."xdg/hypr/hyprtoolkit.conf".text = ''
    background = 0xFF${colors.bg}
    base = 0xFF202020
    alternate_base = 0xFF272727
    text = 0xFFd0d0d8
    bright_text = 0xFFffffff
    accent = 0xFF${colors.blue}
    accent_secondary = 0xFF${colors.cyan}
    h1_size = 19
    h2_size = 15
    h3_size = 13
    font_size = 12
    small_font_size = 10
    font_family = Noto Sans
    font_family_monospace = monospace
    rounding_large = 8
    rounding_small = 4
  '';

  environment.etc."xdg/hypr/hyprlauncher.conf".text = ''
    general {
        grab_focus = true
    }

    cache {
        enabled = true
    }

    finders {
        default_finder = desktop
        math_prefix = =
        font_prefix = '
        desktop_terminal = foot
        desktop_icons = true
    }

    ui {
        window_size = 680 460
    }
  '';

  environment.etc."xdg/waybar/config.jsonc".text = defaultWaybarConfigJson;
  environment.etc."xdg/waybar/style.css".text = defaultWaybarStyleCss;

  # 9. Audio & Media
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = false;
    pulse.enable = true;
    wireplumber.enable = true;
  };

  # 10. User Account & Access
  environment.pathsToLink = [ "/share/zsh" ];

  users.users.root.hashedPassword = "$y$j9T$sGr6gwgrau81kZnyzeqFq1$vzXrHa208anPwSWdR40fZ49l7Keb9A.i1Mw.sDM5rA6";

  users.users.rjpc = {
    isNormalUser = true;
    home = "/home/rjpc";
    description = "Ryan J.P. Casalino";
    shell = "${pkgs.zsh}${pkgs.zsh.shellPath}";
    hashedPassword = "$y$j9T$sGr6gwgrau81kZnyzeqFq1$vzXrHa208anPwSWdR40fZ49l7Keb9A.i1Mw.sDM5rA6";
    extraGroups = [ "wheel" "networkmanager" "video" "audio" "input" ];
    openssh.authorizedKeys.keys = [
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJNo24kFmOht87GEejqv4uWquucROWu4Fw8v8JaElomJ rjpc@zits"
      "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQCvODA0utimDS5vMsmJ8JpcR9VWRIcb8mMPVm5MNZZkvqqnlqSIu0N98aHQJkp3rWEAYHCUWGSDYRi4qjdJ2p/llQSINrZhUwgUWukdUxOwU7Ru0bMZ7aBBoUXjgFFZLF1WlKVETW/wy3O39zb3L/MSTJIrAwwI3trNcqln3EEOix7cyfZteL8FbdTtus0vVAyi5iiqOcx9gv+jGAagxhd7Yh0pWo0a6MZb0sDDbHN8tXC21RFYBKa6IMmJQ505gx0N76bSb6xmSSaH1nb2khttBkT8sdu57uagnE4foDz00hSuBpOrIgawPMTyuyX2hvuDfchHet+/XBzOXH4eudHw92AE2m99cFHgrQuE9aMXN4a/iM3g/3ig1kU86GKaVWg1llzJ3oTjEBNzLXAb2zt9ZBAmkCwd+EF+n35mqD0UiIclyuTgZzUbmF7LCM/tUDaFOSl6PbY0tW6FcN26aFsWEgreTZ6edALKNO/bG7jlCxA+MxAoYgUbdp2Aa5Ywcu76nBECesvQRFaw4khF/+Lj39izA1pwenWM7fVSbX5DF3S0XwTA2OZINIxcVnE48+vup2NH8Oy27Kkc5j7MnlmueRUb9ptvUqk+vTZ49qnxipabp729q+fojoAENUz0xeQugDwVXPBBXTJGg29DYdsUYOxbIvkgY0QQmcKF6snaOw== rjpc@x13s"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDRD43YeRHIv/H4S8Hj9bw0uoGRo0W9mCMMOZvtHPBLi rjpc@air"
      "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMM2gabh4hExixOKrLfrG029dA5TiKyr4SZB5BsJB65o rjpc@YF21"
    ];
  };

  security.sudo.wheelNeedsPassword = false;

  services.openssh = {
    enable = true;
    settings.PasswordAuthentication = true;
  };

  # 11. Essential Packages, Apps & Homelab Tools
  environment.systemPackages = with pkgs; [
    # Core & Hardware
    git
    curl
    wget
    htop
    btop
    powertop
    pciutils
    usbutils
    ethtool
    iw
    wirelesstools
    networkmanager
    bluez
    pulseaudio
    fprintd
    i2c-tools
    libgpiod

    # Terminal, Shell & File Management
    foot
    tmux
    mosh
    sshfs
    direnv
    fd
    ripgrep
    dust
    yazi
    jq
    yq-go
    fastfetch
    fortune

    # Writing, Docs & Reading
    zathura
    typst
    w3m
    newsboat

    # Media & Web (Wayland + Adreno 660 HW Accel)
    firefox
    mpv
    feh
    awww
    waybar
    hyprlauncher
    nwg-look
    apple-cursor
    bibata-cursors
    breeze-hacked-cursor-theme
    catppuccin-cursors
    brightnessctl
    pamixer
    playerctl
    wallpaperChanger

    # Nix & Homelab Secrets / AI Offload
    age
    sops
    nixpkgs-fmt
    nixd
    ollama
    yangStream
    yangLogs
    homelabSecrets
    statusScript
    panelScript
    swayWindowSwitcher
  ];

  # 12. Custom Vim Configuration (from zits editor.nix: Habamax + PaperMode + Plugins)
  programs.vim = {
    enable = true;
    defaultEditor = true;
    package = (pkgs.vim-full.override { }).customize {
      name = "vim";
      vimrcConfig.packages.myplugins = with pkgs.vimPlugins; {
        start = [
          ale
          colorizer
          copilot-vim
          csv-vim
          lightline-vim
          matchit-zip
          vim-go
          vim-nix
          vim-terraform
          vim-lsp
          vim-lastplace
          vim-signify
        ];
        opt = [ ];
      };
      vimrcConfig.customRC = ''
          set nocompatible
          filetype plugin indent on

          set noswapfile
          set nobackup
          set nowritebackup

          set scrolloff=8
          set signcolumn=yes
          set updatetime=100
          set hidden

          set ignorecase
          set smartcase
          set incsearch
          set hlsearch
          set termguicolors

          set number
          set relativenumber

          if !has('gui_running')
              set t_Co=256
          endif

          colorscheme habamax
          syntax on
          set expandtab
          set tabstop=4
          set ruler
          set spelllang=en_us
          set list
          set listchars=eol:¬,tab:▸\ ,trail:·
          set wildmenu
          set wildmode=longest,list,full

          let g:netrw_preview = 1
          let g:netrw_banner = 1
          let g:netrw_liststyle = 3
          let g:netrw_winsize = 25

          let g:ale_sign_error = '✘'
          let g:ale_sign_warning = '⚠'
          highlight ALEErrorSign ctermbg=NONE ctermfg=red
          highlight ALEWarningSign ctermbg=NONE ctermfg=yellow

          noremap <F11> :tabprevious<CR>
          noremap <F12> :tabnext<CR>

          augroup vimrc
              autocmd!
              au BufRead,BufNewFile *.tex,*.md,*.txt,*.man,*.ms setlocal spell
              hi clear SpellBad
              hi SpellBad cterm=underline,bold ctermfg=red
          augroup END

          augroup PaperMode
              autocmd!
              autocmd BufEnter *.txt,*.tex set background=light
              autocmd BufEnter *.txt,*.tex highlight Normal     ctermbg=231 ctermfg=235 guibg=#FFFFFF guifg=#1c1c1c
              autocmd BufEnter *.txt,*.tex highlight NonText    ctermbg=231 ctermfg=235 guibg=#FFFFFF guifg=#1c1c1c
              autocmd BufEnter *.txt,*.tex highlight Cursor     ctermfg=231 ctermbg=196 guifg=#FFFFFF guibg=#FF0000
              autocmd BufEnter *.txt,*.tex highlight CursorLine cterm=NONE ctermbg=254 guibg=#e4e4e4

              autocmd BufEnter *.txt,*.tex set syntax=off
              autocmd BufEnter *.txt,*.tex set spell!
              autocmd BufEnter *.txt,*.tex set cursorline
              autocmd BufEnter *.txt,*.tex set guicursor=a:block-Cursor

              autocmd BufEnter *.txt,*.tex let &t_EI = "\<Esc>]12;#FF0000\x7"
              autocmd BufEnter *.txt,*.tex let &t_SI = "\<Esc>]12;#FF0000\x7"
              autocmd BufEnter *.txt,*.tex let &t_SR = "\<Esc>]12;#FF0000\x7"
              autocmd BufEnter *.txt,*.tex silent! execute "normal! \<Esc>"

              autocmd BufLeave *.txt,*.tex set background=dark
              autocmd BufLeave *.txt,*.tex set nocursorline
              autocmd BufLeave *.txt,*.tex set guicursor=
              autocmd BufLeave *.txt,*.tex highlight clear CursorLine
              autocmd BufLeave *.txt,*.tex highlight Normal ctermbg=NONE ctermfg=NONE guibg=NONE guifg=NONE
              autocmd BufLeave *.txt,*.tex highlight NonText ctermbg=NONE ctermfg=NONE guibg=NONE guifg=NONE

              autocmd BufLeave *.txt,*.tex silent! execute "normal! \<Esc>"
          augroup END

          autocmd VimLeave * silent !echo -ne "\033]112\007"
          set laststatus=0
          runtime macros/matchit.vim
      '';
    };
  };

  # 13. Foot Terminal & Zsh / Starship (matching zits)
  programs.foot = {
    enable = true;
    enableZshIntegration = true;

    settings = {
      main = {
        font = "monospace:size=12.5";
      };

      cursor = {
        blink = "yes";
        style = "underline";
      };

      colors-dark = {
        # Midnight 2026 Prompt Vibe (Cool Soft Black / Muted Pastels)
        cursor = "141417 7e9cd8";
        background = "141417";
        foreground = "d0d0d8";

        # Normal colors
        regular0 = "1c1c22"; # black
        regular1 = "d97c8a"; # red (Muted Rose)
        regular2 = "8abf9c"; # green (Muted Mint)
        regular3 = "d4b47b"; # yellow (Soft Gold)
        regular4 = "7e9cd8"; # blue (Powder Blue)
        regular5 = "b893ce"; # magenta (Dusty Lavender)
        regular6 = "78b5ba"; # cyan (Soft Cyan)
        regular7 = "a0a0ab"; # white

        # Bright colors
        bright0 = "68687a"; # bright black (Muted Slate)
        bright1 = "e38e9a"; # bright red (lighter rose)
        bright2 = "9ecfbc"; # bright green (lighter mint)
        bright3 = "e6c891"; # bright yellow (lighter gold)
        bright4 = "90aee6"; # bright blue (lighter powder blue)
        bright5 = "c6a3db"; # bright magenta (lighter lavender)
        bright6 = "8bc6cb"; # bright cyan (lighter cyan)
        bright7 = "d0d0d8"; # bright white
      };

      key-bindings = {
        font-increase = "Control+plus Control+equal Control+KP_Add Mod4+plus Mod4+equal Mod4+KP_Add";
        font-decrease = "Control+minus Control+KP_Subtract Mod4+minus Mod4+KP_Subtract";
        font-reset = "Control+0 Control+KP_0 Mod4+0 Mod4+KP_0";
      };
    };
  };

  programs.zsh = {
    enable = true;
    autosuggestions.enable = true;
    syntaxHighlighting.enable = true;
    histSize = 10000;
    histFile = "$HOME/.zsh_history";

    setOptions = [
      "HIST_IGNORE_ALL_DUPS"
      "HIST_FIND_NO_DUPS"
      "HIST_REDUCE_BLANKS"
    ];

    shellAliases = {
      ".." = "cd ..";
      "..." = "cd ../..";
      "dc" = "docker compose";
      "ddie" = "docker system prune -a --volumes";
      "de" = "docker exec -it";
      "dnin" = "docker network inspect";
      "dnls" = "docker network ls";
      "dps" = "docker ps";
      "fd" = "fd -c never";
      "g" = "git";
      "ll" = "ls -l";
      "ls" = "ls --color=auto";
      "nd" = "nix develop";
      "arty" = "sudo nixos-rebuild switch --flake /etc/nixos#arty";
      "ai" = "yang-stream";
      "ai-code" = "yang-stream --model qwen2.5-coder:14b";
      "ai-zits" = "yang-stream --host http://zits.home.arpa:11434 --model muse-glimmer:latest";
    };

    interactiveShellInit = ''
      # Zsh configuration is managed system-wide in /etc/zshrc; disable the
      # first-run wizard when no ~/.z* dotfile is present in $HOME.
      zsh-newuser-install() { :; }

      eval "$(direnv hook zsh)"
      # Force Vim keybindings (human edit)
      bindkey -v
      # reverse search
      bindkey '^R' history-incremental-search-backward
      # Explicitly bind Ctrl+A to beginning of line
      bindkey '^A' beginning-of-line
      # Explicitly bind Ctrl+E to end of line
      bindkey '^E' end-of-line
      # Fix Ctrl+Left and Ctrl+Right for jumping between words
      bindkey '^[[1;5D' backward-word
      bindkey '^[[1;5C' forward-word
      # set erase character based on terminal emulator
      if [[ "$TERM" == "xterm" ]] || [[ "$TERM" == "xterm-color" ]]; then
          stty erase '^H'
      else
          stty erase '^?'
      fi
      # Set the path for your custom log file
      export CMD_LOG_FILE="$HOME/.advanced_history.log"
      export CMD_LOG_STATE="$HOME/.cmdlogger_active"

      # State variables to pass data between hooks
      typeset -g _cmdlogger_start_time
      typeset -g _cmdlogger_current_cmd

      # The control interface
      cmdlogger() {
          case "$1" in
              start)
                  touch "$CMD_LOG_STATE"
                  echo "Logging enabled. Outputting to $CMD_LOG_FILE" ;;
              stop)
                  rm -f "$CMD_LOG_STATE"
                  echo "Logging disabled." ;;
              *) echo "Usage: cmdlogger {start|stop}" ;;
          esac
      }

      # Hook 1: Runs right before execution
      preexec() {
          if [[ -f "$CMD_LOG_STATE" ]]; then
              _cmdlogger_start_time=$(date +%s)
              _cmdlogger_current_cmd="$1"
          fi
      }

      # Hook 2: Runs immediately after the command finishes
      precmd() {
          local exit_code=$?

          if [[ -f "$CMD_LOG_STATE" && -n "$_cmdlogger_current_cmd" ]]; then
              local end_time=$(date +%s)
              local duration=$(( end_time - _cmdlogger_start_time ))
              local timestamp=$(date '+%Y-%m-%d %H:%M:%S')

              local env_state=""
              if [[ -n "$IN_NIX_SHELL" ]]; then
                  env_state="[nix] "
              fi

              echo "[$timestamp] [Status: $exit_code] [$duration s] $USER $env_state$PWD > $_cmdlogger_current_cmd" >> "$CMD_LOG_FILE"

              _cmdlogger_current_cmd=""
          fi
      }
    '';
  };

  programs.starship = {
    enable = true;
    settings = {
      add_newline = true;

      format = ''
        $time$username$hostname$directory$git_branch$git_status$nix_shell$cmd_duration
        $character
      '';

      time = {
        disabled = false;
        time_format = "%H:%M:%S";
        style = "bold #68687a";
        format = "[\\[$time\\]]($style) ";
      };

      username = {
        show_always = true;
        style_user = "bold #8abf9c";
        style_root = "bold #d97c8a";
        format = "[\\[$user]($style)";
      };

      hostname = {
        ssh_only = false;
        style = "bold #8abf9c";
        format = "[@$hostname\\]]($style) ";
      };

      directory = {
        style = "bold #78b5ba";
        format = "[\\[ $path \\]]($style) ";
        truncation_length = 4;
        truncate_to_repo = false;
      };

      git_branch = {
        style = "bold #b893ce";
        symbol = "";
        format = "[{ $branch }]($style)";
      };

      git_status = {
        style = "bold #d4b47b";
        format = " [\\[$all_status$ahead_behind\\]]($style) ";
        conflicted = "X";
        ahead = "↑\${count}";
        behind = "↓\${count}";
        diverged = "↕\${ahead_count} \${behind_count}";
        untracked = "?";
        modified = "!";
        staged = "+";
        deleted = "-";
      };

      nix_shell = {
        style = "bold #7e9cd8";
        symbol = "";
        format = "[\\( nix: $state \\)]($style) ";
      };

      cmd_duration = {
        style = "bold #68687a";
        format = "[~ $duration]($style) ";
      };

      character = {
        success_symbol = "[>_](#8abf9c)";
        error_symbol = "[>_](#d97c8a)";
        vimcmd_symbol = "[<_](#7e9cd8)";
      };
    };
  };

  nix.settings = {
    experimental-features = [ "nix-command" "flakes" ];
    trusted-users = [ "root" "rjpc" ];
  };

  system.stateVersion = "24.11";
}
