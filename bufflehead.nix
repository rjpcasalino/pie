{ config, pkgs, lib, ... }:

{
  imports = [
    ./bh-hardware-configuration.nix
  ];

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  boot.kernelPackages = pkgs.linuxPackages_latest;

  networking.hostName = "bufflehead";
  networking.wireless = {
    enable = true;
    userControlled = true;
    iwd.enable = false;
    scanOnLowSignal = true;
    secretsFile = "/etc/wpa_supplicant/wireless.env";
    networks = {
      "12AngryPeople" = {
        pskRaw = "ext:PSK";
      };
    };
  };

  networking.useDHCP = false;
  networking.interfaces.eno1.useDHCP = true;
  networking.interfaces.wlp0s20f3.useDHCP = true;
  networking.nameservers = [ "192.168.12.80" "127.0.0.1" ];
  networking.enableIPv6 = true;
  networking.firewall.allowedTCPPorts = [ 53 80 443 2283 8085 8086 ];
  networking.firewall.allowedUDPPorts = [ 53 ];
  networking.firewall.enable = true;
  security.pki.certificateFiles = [ ./certs/rock-ca.crt ];
  services.gpm.enable = false;

  i18n.defaultLocale = "en_US.UTF-8";

  console = {
    earlySetup = true;
    font = "${pkgs.terminus_font}/share/consolefonts/ter-v18n.psf.gz";
    packages = with pkgs; [ terminus_font ];
    keyMap = "us";
  };

  fonts.packages = with pkgs; [
    noto-fonts
  ];

  time.timeZone = "America/Los_Angeles";

  nixpkgs.hostPlatform = "x86_64-linux";
  nixpkgs.overlays = [
    (self: super: {
      mpv-unwrapped = super.mpv-unwrapped.override {
        libbluray = super.libbluray.override {
          withAACS = true;
          withBDplus = true;
        };
      };
    })
  ];
  nixpkgs.config.packageOverrides = pkgs: {
    vaapiIntel = pkgs.intel-vaapi-driver.override { enableHybridCodec = true; };
  };
  nixpkgs.config.allowUnfree = true;

  nix = {
    settings = {
      auto-optimise-store = true;
      trusted-users = [ "@wheel" ];
    };
    extraOptions = ''
      experimental-features = nix-command flakes
    '';
  };

  hardware.graphics = {
    enable = true;
    extraPackages = with pkgs; [
      intel-media-driver # LIBVA_DRIVER_NAME=iHD
      vaapiIntel # LIBVA_DRIVER_NAME=i965 (older but works better for Firefox/Chromium)
      libva-vdpau-driver
      libvdpau-va-gl
    ];
  };

  hardware.bluetooth = {
    enable = false;
    powerOnBoot = true;
    settings = {
      General = {
        Name = "Bufflehead";
        ControllerMode = "dual";
        FastConnectable = "true";
        Experimental = "true";
      };
      Policy = { AutoEnable = "true"; };
      LE = { EnableAdvMonInterleaveScan = "true"; };
    };
  };

  hardware.enableAllFirmware = true;
  hardware.enableRedistributableFirmware = true;

  services.xserver = {
    enable = true;
    xkb.layout = "us";
    autorun = false;
    exportConfiguration = true;
    displayManager.startx.enable = true;
    windowManager.cwm.enable = true;
    videoDrivers = [ "modesetting" ];
  };

  ## MY BOOK 14.6TB BTRFS POOL
  fileSystems."/mnt/mybook" = {
    device = "/dev/disk/by-uuid/23e182bf-65d2-48c4-92b0-cda956920019";
    fsType = "btrfs";
    options = [ "compress=zstd" "noatime" "nofail" ];
  };

  ## MINIDLNA
  services.minidlna = {
    enable = true;
    openFirewall = true;
    settings.media_dir = [ "/mnt/sdc1" "/mnt/sdd1" "/mnt/sdb1" "/mnt/wdblack" "/mnt/mybook/media" ];
    settings.inotify = "yes";
  };
  systemd.services.minidlna = {
    after = [ "mnt-sdb1.mount" "mnt-sdc1.mount" "mnt-sdd1.mount" "mnt-wdblack.mount" "mnt-mybook.mount" ];
    wants = [ "mnt-sdb1.mount" "mnt-sdc1.mount" "mnt-sdd1.mount" "mnt-wdblack.mount" "mnt-mybook.mount" ];
  };

  ## KIWIX OFFLINE KNOWLEDGE SERVER
  services.kiwix-serve = {
    enable = true;
    port = 8085;
    openFirewall = true;
    libraryPath = "/mnt/wdblack/kiwix/library.xml";
    extraArgs = [ "-M" ];
  };
  systemd.services.kiwix-serve = {
    after = [ "mnt-wdblack.mount" ];
    wants = [ "mnt-wdblack.mount" ];
  };

  ## OPDS READING ROOM SERVER (KOReader / Kindle)
  systemd.services.opds-server = {
    description = "Bufflehead OPDS 1.2 Reading Room Server";
    after = [ "network.target" "mnt-wdblack.mount" ];
    wants = [ "mnt-wdblack.mount" ];
    wantedBy = [ "multi-user.target" ];
    serviceConfig = {
      ExecStart = "${pkgs.python3}/bin/python3 /home/rjpc/.local/bin/opds-server.py";
      Restart = "on-failure";
      RestartSec = 5;
      User = "rjpc";
    };
  };

  ## KIWIX AUTOMATIC UPDATE SERVICE & TIMER
  systemd.services.kiwix-update = {
    description = "Synchronize Kiwix ZIM Knowledge Bases with Upstream";
    after = [ "network-online.target" "mnt-wdblack.mount" ];
    wants = [ "network-online.target" "mnt-wdblack.mount" ];
    path = with pkgs; [ bash curl kiwix-tools gnugrep coreutils systemd gawk ];
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "/opt/kiwix/kiwix-update.sh";
      User = "root";
    };
  };

  systemd.timers.kiwix-update = {
    description = "Weekly Kiwix Knowledge Base Synchronization Timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "Sun *-*-* 03:00:00";
      Persistent = true;
    };
  };

  ## IMMICH PHOTO MANAGEMENT SERVER
  services.postgresql.package = pkgs.postgresql_16;
  services.immich = {
    enable = true;
    host = "0.0.0.0";
    port = 2283;
    mediaLocation = "/mnt/wdblack/immich";
    openFirewall = true;
    machine-learning.enable = false;
  };
  systemd.services.immich-server = {
    after = [ "mnt-wdblack.mount" ];
    wants = [ "mnt-wdblack.mount" ];
    environment.IMMICH_MACHINE_LEARNING_URL = lib.mkForce "http://yang.home.arpa:3003";
  };

  ## PLUG-AND-INGEST SD/MICROSD CAMERA CARD DROP-BOX (UDEV + SYSTEMD -> IMMICH + MYBOOK)
  services.udev.extraRules = ''
    SUBSYSTEM=="block", KERNEL=="mmcblk[0-9]p[0-9]*", ACTION=="add", TAG+="systemd", ENV{SYSTEMD_WANTS}+="sdcard-ingest@%k.service"
  '';

  systemd.services."sdcard-ingest@" = {
    description = "Auto-Ingest Camera SD/microSD Card (%I) into Immich and /mnt/mybook Archive";
    after = [ "immich-server.service" "postgresql.service" "mnt-mybook.mount" ];
    wants = [ "immich-server.service" ];
    path = with pkgs; [ bash coreutils curl util-linux python3 sudo config.services.postgresql.package ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = "${pkgs.python3}/bin/python3 /etc/immich-sdcard-ingest.py %I";
    };
  };

  environment.etc."immich-sdcard-ingest.py" = {
    mode = "0755";
    text = ''
      #!/usr/bin/env python3
      import concurrent.futures
      import datetime
      import hashlib
      import json
      import os
      import secrets
      import shutil
      import subprocess
      import sys
      import time
      import urllib.request

      IMMICH_URL = "http://127.0.0.1:2283"
      STATE_DIR = "/var/lib/immich-ingest"
      KEY_FILE = os.path.join(STATE_DIR, "api.key")
      CACHE_FILE = os.path.join(STATE_DIR, "uploaded-cache.json")
      LOG_FILE = os.path.join(STATE_DIR, "ingest.log")
      ARCHIVE_ROOT = "/mnt/mybook/archive/sdcard-imports"
      ALBUM_NAME = "Camera SD Imports"
      MEDIA_EXTS = {
          ".jpg", ".jpeg", ".cr2", ".cr3", ".nef", ".arw", ".dng", ".orf",
          ".rw2", ".pef", ".raf", ".heic", ".heif", ".png", ".mp4", ".mov",
          ".m4v", ".avi", ".mts", ".m2ts", ".3gp", ".wav"
      }

      def log(msg):
          ts = datetime.datetime.now().strftime("%Y-%m-%d %H:%M:%S")
          line = f"[{ts}] {msg}"
          print(line, flush=True)
          try:
              os.makedirs(STATE_DIR, exist_ok=True)
              with open(LOG_FILE, "a") as f:
                  f.write(line + "\n")
          except Exception:
              pass

      def ensure_api_key():
          os.makedirs(STATE_DIR, exist_ok=True)
          os.chmod(STATE_DIR, 0o700)
          if os.path.exists(KEY_FILE):
              token = open(KEY_FILE).read().strip()
              if token:
                  try:
                      req = urllib.request.Request(f"{IMMICH_URL}/api/users/me", headers={"x-api-key": token})
                      with urllib.request.urlopen(req, timeout=5) as resp:
                          if resp.status == 200:
                              return token
                  except Exception:
                      pass
          token = secrets.token_urlsafe(32).replace("-", "").replace("_", "")
          digest_hex = hashlib.sha256(token.encode()).hexdigest()
          sql = (
              "DELETE FROM api_key WHERE name='bufflehead-sdcard-ingest'; "
              "INSERT INTO api_key (name, key, \"userId\", permissions) "
              f"SELECT 'bufflehead-sdcard-ingest', decode('{digest_hex}', 'hex'), id, '{{all}}' "
              "FROM \"user\" WHERE \"isAdmin\" = true ORDER BY \"createdAt\" ASC LIMIT 1;"
          )
          subprocess.run(["sudo", "-u", "postgres", "psql", "-d", "immich", "-tAc", sql], check=True)
          with open(KEY_FILE, "w") as f:
              f.write(token + "\n")
          os.chmod(KEY_FILE, 0o600)
          return token

      def ensure_album(token):
          req = urllib.request.Request(f"{IMMICH_URL}/api/albums", headers={"x-api-key": token})
          with urllib.request.urlopen(req, timeout=10) as resp:
              albums = json.loads(resp.read().decode())
          for a in albums:
              if a.get("albumName") == ALBUM_NAME:
                  return a["id"]
          body = json.dumps({
              "albumName": ALBUM_NAME,
              "description": "Automatically ingested from SD/microSD cards inserted into bufflehead"
          }).encode()
          req = urllib.request.Request(
              f"{IMMICH_URL}/api/albums",
              data=body,
              headers={"x-api-key": token, "Content-Type": "application/json"},
              method="POST"
          )
          with urllib.request.urlopen(req, timeout=10) as resp:
              return json.loads(resp.read().decode())["id"]

      def add_to_album(token, album_id, asset_ids):
          if not asset_ids:
              return
          for i in range(0, len(asset_ids), 100):
              chunk = asset_ids[i:i + 100]
              body = json.dumps({"ids": chunk}).encode()
              req = urllib.request.Request(
                  f"{IMMICH_URL}/api/albums/{album_id}/assets",
                  data=body,
                  headers={"x-api-key": token, "Content-Type": "application/json"},
                  method="PUT"
              )
              try:
                  urllib.request.urlopen(req, timeout=15).read()
              except Exception as e:
                  log(f"WARN: album add error: {e}")

      def main():
          part = sys.argv[1] if len(sys.argv) > 1 else "mmcblk0p1"
          part = os.path.basename(part)
          dev = f"/dev/{part}"
          if not os.path.exists(dev):
              log(f"Device {dev} does not exist; exiting.")
              return 0

          for _ in range(15):
              try:
                  urllib.request.urlopen(f"{IMMICH_URL}/api/server/ping", timeout=3).read()
                  break
              except Exception:
                  time.sleep(2)

          uuid = subprocess.run(
              ["blkid", "-s", "UUID", "-o", "value", dev],
              capture_output=True, text=True
          ).stdout.strip() or part

          mnt = f"/run/sdcard-ingest/{part}"
          os.makedirs(mnt, exist_ok=True)
          mounted = False
          try:
              subprocess.run(["mount", "-o", "ro", dev, mnt], check=True)
              mounted = True
              log(f"Mounted {dev} (UUID={uuid}) read-only at {mnt}")

              media_files = []
              for root, dirs, files in os.walk(mnt):
                  dirs[:] = [d for d in dirs if not d.startswith(".") and d != "System Volume Information"]
                  for fn in sorted(files):
                      if fn.startswith(".") or fn.startswith("._"):
                          continue
                      ext = os.path.splitext(fn)[1].lower()
                      if ext in MEDIA_EXTS:
                          full = os.path.join(root, fn)
                          rel = os.path.relpath(full, mnt)
                          media_files.append((full, rel))

              log(f"Discovered {len(media_files)} media files on {dev} (UUID={uuid})")
              if not media_files:
                  return 0

              # 1. Archival copy to /mnt/mybook/archive/sdcard-imports/<UUID>/
              archived_new = 0
              if os.path.ismount("/mnt/mybook"):
                  card_archive = os.path.join(ARCHIVE_ROOT, uuid)
                  for full, rel in media_files:
                      dst = os.path.join(card_archive, rel)
                      st = os.stat(full)
                      if not os.path.exists(dst) or os.path.getsize(dst) != st.st_size:
                          os.makedirs(os.path.dirname(dst), exist_ok=True)
                          shutil.copy2(full, dst)
                          archived_new += 1
                  subprocess.run(["chown", "-R", "rjpc:users", card_archive], check=False)
                  log(f"Archive sync to {card_archive} complete ({archived_new} new files copied)")

              # 2. Immich upload
              token = ensure_api_key()
              album_id = ensure_album(token)
              cache = {}
              if os.path.exists(CACHE_FILE):
                  try:
                      cache = json.load(open(CACHE_FILE))
                  except Exception:
                      cache = {}

              to_upload = []
              cached_skip = 0
              for full, rel in media_files:
                  st = os.stat(full)
                  ck = f"{uuid}:{rel}:{st.st_size}:{int(st.st_mtime)}"
                  if ck in cache:
                      cached_skip += 1
                  else:
                      to_upload.append((full, rel, st, ck))

              log(f"Immich ingest: {len(to_upload)} to process, {cached_skip} already in local cache")

              def upload_one(item):
                  full, rel, st, ck = item
                  h = hashlib.sha1()
                  with open(full, "rb") as f:
                      while chunk := f.read(1048576):
                          h.update(chunk)
                  sha1 = h.hexdigest()
                  mtime_iso = datetime.datetime.fromtimestamp(st.st_mtime, tz=datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")
                  dev_asset_id = f"sdcard-{uuid}-{rel}-{st.st_size}"
                  cmd = [
                      "curl", "-sS", "-X", "POST", f"{IMMICH_URL}/api/assets",
                      "-H", f"x-api-key: {token}",
                      "-H", f"x-immich-checksum: {sha1}",
                      "-F", f"assetData=@{full}",
                      "-F", f"deviceAssetId={dev_asset_id}",
                      "-F", "deviceId=bufflehead-sdcard-ingest",
                      "-F", f"fileCreatedAt={mtime_iso}",
                      "-F", f"fileModifiedAt={mtime_iso}",
                  ]
                  res = subprocess.run(cmd, capture_output=True, text=True)
                  if res.returncode != 0:
                      return (ck, None, f"curl error: {res.stderr}")
                  try:
                      data = json.loads(res.stdout)
                      return (ck, data.get("id"), data.get("status", "unknown"))
                  except Exception:
                      return (ck, None, f"bad json: {res.stdout[:120]}")

              created = 0
              duplicates = 0
              errors = 0
              asset_ids = []
              with concurrent.futures.ThreadPoolExecutor(max_workers=4) as ex:
                  for idx, (ck, aid, status) in enumerate(ex.map(upload_one, to_upload), 1):
                      if aid:
                          cache[ck] = aid
                          asset_ids.append(aid)
                          if status == "created":
                              created += 1
                          else:
                              duplicates += 1
                      else:
                          errors += 1
                          log(f"WARN: failed {ck}: {status}")
                      if idx % 50 == 0 or idx == len(to_upload):
                          log(f"Progress: {idx}/{len(to_upload)} (created={created}, duplicate={duplicates}, errors={errors})")

              with open(CACHE_FILE, "w") as f:
                  json.dump(cache, f)

              add_to_album(token, album_id, asset_ids)
              log(f"DONE {dev} (UUID={uuid}): total={len(media_files)}, archived_new={archived_new}, immich_created={created}, immich_duplicate={duplicates}, cached_skip={cached_skip}, errors={errors}")
          finally:
              if mounted:
                  subprocess.run(["umount", mnt], check=False)
                  log(f"Unmounted {mnt} cleanly (card is safe to remove)")
          return 0

      if __name__ == "__main__":
          sys.exit(main())
    '';
  };

  ## VAULTWARDEN PASSWORD MANAGER
  services.vaultwarden = {
    enable = true;
    config = {
      ROCKET_ADDRESS = "127.0.0.1";
      ROCKET_PORT = 8222;
      DOMAIN = "https://vault.home.arpa";
      SIGNUPS_ALLOWED = false;
      INVITATIONS_ALLOWED = true;
      SHOW_PASSWORD_HINT = false;
    };
  };

  ## VAULTWARDEN NIGHTLY BACKUP SERVICE & TIMER
  systemd.services.vaultwarden-backup = {
    description = "Backup Vaultwarden SQLite Database and Data to Rock Vault";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    path = with pkgs; [ bash coreutils gnutar gzip iputils openssh sqlite.bin ];
    serviceConfig = {
      Type = "oneshot";
      User = "root";
      ExecStart = pkgs.writeShellScript "vaultwarden-backup.sh" ''
        set -euo pipefail
        DATA_DIR="/var/lib/bitwarden_rs"
        if [ -d "/var/lib/vaultwarden" ]; then
          DATA_DIR="/var/lib/vaultwarden"
        fi
        BACKUP_DIR="/var/backup/vaultwarden"
        mkdir -p "$BACKUP_DIR"
        chmod 700 "$BACKUP_DIR"

        # 1. Atomic SQLite online backup
        if [ -f "$DATA_DIR/db.sqlite3" ]; then
          sqlite3 "$DATA_DIR/db.sqlite3" ".backup '$BACKUP_DIR/db.sqlite3'"
        fi

        # 2. Archive RSA keys and attachments
        if [ -d "$DATA_DIR" ]; then
          tar -czf "$BACKUP_DIR/vaultwarden-data.tar.gz" \
            -C "$DATA_DIR" \
            --exclude='*.sqlite3*' \
            . 2>/dev/null || true
        fi

        # 3. Synchronize to rock.home.arpa:/vault/vaultwarden/ (encrypted softraid0)
        if ping -c 1 -W 2 192.168.12.80 >/dev/null 2>&1; then
          ssh -i /root/.ssh/id_ed25519 -o StrictHostKeyChecking=no root@192.168.12.80 "mkdir -p /vault/vaultwarden && chmod 700 /vault/vaultwarden"
          scp -i /root/.ssh/id_ed25519 -o StrictHostKeyChecking=no "$BACKUP_DIR"/* root@192.168.12.80:/vault/vaultwarden/
        fi
      '';
    };
  };

  systemd.timers.vaultwarden-backup = {
    description = "Nightly Vaultwarden Backup Timer";
    wantedBy = [ "timers.target" ];
    timerConfig = {
      OnCalendar = "*-*-* 04:00:00";
      Persistent = true;
    };
  };

  ## CADDY SECURE REVERSE PROXY (:443)
  services.caddy = {
    enable = true;
    extraConfig = ''
      kiwix.home.arpa {
        tls /etc/ssl/ca/wildcard.fullchain.crt /etc/ssl/ca/wildcard.key
        reverse_proxy 127.0.0.1:8085
      }

      http://photos.home.arpa, http://immich.home.arpa, http://192.168.12.122 {
        reverse_proxy 127.0.0.1:2283
      }

      https://photos.home.arpa, https://immich.home.arpa, https://192.168.12.122 {
        tls /etc/ssl/ca/wildcard.fullchain.crt /etc/ssl/ca/wildcard.key
        reverse_proxy 127.0.0.1:2283
      }

      vault.home.arpa {
        tls /etc/ssl/ca/wildcard.fullchain.crt /etc/ssl/ca/wildcard.key
        reverse_proxy 127.0.0.1:8222
      }
    '';
  };
  ##
  services.openssh = {
    enable = true;
    settings = {
      PasswordAuthentication = false;
      PermitRootLogin = "no";
      KbdInteractiveAuthentication = false;
    };
  };

  users.users.rjpc = {
    isNormalUser = true;
    extraGroups = [
      "adbusers"
      "audio"
      "cdrom"
      "lp"
      "lxd"
      "sound"
      "wheel"
    ];
    openssh.authorizedKeys.keys = [ "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIJNo24kFmOht87GEejqv4uWquucROWu4Fw8v8JaElomJ rjpc@zits" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIDRD43YeRHIv/H4S8Hj9bw0uoGRo0W9mCMMOZvtHPBLi rjpc@air" "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMM2gabh4hExixOKrLfrG029dA5TiKyr4SZB5BsJB65o rjpc@YF21" ];
    packages = with pkgs; [ ];
  };

  security.sudo = {
    enable = true;
    wheelNeedsPassword = false;
  };

  environment.systemPackages = with pkgs; [
    vim
    wget
    mpv-unwrapped
    nixpkgs-fmt
    fastfetch
    kiwix-tools
    (pkgs.writeShellScriptBin "sdcard-ingest" ''
      PART="''${1:-mmcblk0p1}"
      PART="''${PART#/dev/}"
      echo "Starting sdcard-ingest@''${PART}.service..."
      sudo systemctl start "sdcard-ingest@''${PART}.service"
      sudo tail -n 20 /var/lib/immich-ingest/ingest.log
    '')
  ];

  # Secondary LAN DNS Resolver (failover for rock.home.arpa)
  services.unbound = {
    enable = true;
    settings = {
      server = {
        interface = [ "0.0.0.0" "::0" ];
        port = 53;
        access-control = [
          "127.0.0.0/8 allow"
          "192.168.12.0/24 allow"
          "::1 allow"
        ];
        private-domain = [ "home.arpa" ];
        local-zone = [ ''"home.arpa." static'' ];
        local-data = [
          ''"rock.home.arpa. IN A 192.168.12.80"''
          ''"bridge.home.arpa. IN A 192.168.12.212"''
          ''"zits.home.arpa. IN A 192.168.12.58"''
          ''"bufflehead.home.arpa. IN A 192.168.12.122"''
          ''"kiwix.home.arpa. IN A 192.168.12.122"''
          ''"photos.home.arpa. IN A 192.168.12.122"''
          ''"immich.home.arpa. IN A 192.168.12.122"''
          ''"vault.home.arpa. IN A 192.168.12.122"''
          ''"peloton.home.arpa. IN A 192.168.12.91"''
          ''"yang.home.arpa. IN A 192.168.12.69"''
          ''"zerocool.home.arpa. IN A 192.168.12.130"''
          ''"arty.home.arpa. IN A 192.168.12.131"''
        ];
        tls-cert-bundle = "/etc/ssl/certs/ca-bundle.crt";
      };
      forward-zone = [
        {
          name = ".";
          forward-tls-upstream = true;
          forward-addr = [
            "1.1.1.3@853#family.cloudflare-dns.com"
            "1.0.0.3@853#family.cloudflare-dns.com"
          ];
        }
      ];
    };
  };

  system.stateVersion = "22.11"; # Did you read the comment? Yes.
}
