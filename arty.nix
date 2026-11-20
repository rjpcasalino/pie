{ config, lib, pkgs, ... }:

{
  imports = [
    ./arty-hardware-configuration.nix
  ];

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

  # 5. Networking & Host Identity
  networking.hostName = "arty";
  networking.networkmanager.enable = true;
  networking.nameservers = [ "192.168.12.80" "1.1.1.3" ];

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

  # 8. Desktop & Display (GNOME Wayland & Sway with Adreno HW Accel)
  services.xserver.enable = true;
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;
  programs.sway.enable = true;

  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "rjpc";

  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  # 9. Audio & Media
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = false;
    pulse.enable = true;
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

  # 11. Essential Packages & Utilities
  environment.systemPackages = with pkgs; [
    vim
    git
    curl
    wget
    htop
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
    foot
    direnv
    fd
    ripgrep
    fastfetch
  ];

  # 12. Foot Terminal & Zsh / Starship (matching zits)
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
