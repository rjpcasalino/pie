#!/usr/bin/env bash
# build-nixos-manual-zim.sh - Build and deploy NixOS Manual ZIM for Kiwix
set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
WORK_DIR="/tmp/nixos-manual-build"
OUT_ZIM="/tmp/nixos_manual_en_26.11.zim"
DEST_HOST="bufflehead.home.arpa"
DEST_DIR="/mnt/wdblack/kiwix"

echo "=== [1/4] Building NixOS HTML Manual via Nix ==="
MANUAL_PATH=$(nix build --no-link --print-out-paths "${SCRIPT_DIR}#nixosConfigurations.bufflehead.config.system.build.manual.manualHTML")/share/doc/nixos
echo "Manual located at: ${MANUAL_PATH}"

echo "=== [2/4] Staging and Generating ZIM Logo ==="
rm -rf "${WORK_DIR}"
mkdir -p "${WORK_DIR}"
cp -r "${MANUAL_PATH}/." "${WORK_DIR}/"
chmod -R u+w "${WORK_DIR}"

# Generate 48x48 Nix blue logo
python3 -c '
import zlib, struct
w, h = 48, 48
raw = b""
for y in range(h):
    raw += b"\x00"
    for x in range(w):
        raw += bytes([82, 119, 195]) # Nix blue #5277C3

def chunk(tag, data):
    return struct.pack(">I", len(data)) + tag + data + struct.pack(">I", zlib.crc32(tag + data) & 0xffffffff)

png = b"\x89PNG\r\n\x1a\n"
png += chunk(b"IHDR", struct.pack(">IIBBBBB", w, h, 8, 2, 0, 0, 0))
png += chunk(b"IDAT", zlib.compress(raw))
png += chunk(b"IEND", b"")
with open("'"${WORK_DIR}"'/logo.png", "wb") as f:
    f.write(png)
'

echo "=== [3/4] Packaging with zimwriterfs ==="
ZIM_TOOLS=$(nix build --no-link --print-out-paths nixpkgs#zim-tools)/bin/zimwriterfs
"${ZIM_TOOLS}" \
  -w index.html \
  -I logo.png \
  -l eng \
  -n nixos-manual \
  -t "NixOS 26.11 Manual" \
  -d "Official NixOS 26.11 System Configuration & Administration Manual" \
  -c "NixOS Foundation" \
  -p "12AngryPeople" \
  "${WORK_DIR}" \
  "${OUT_ZIM}"

echo "=== [4/4] Deploying to ${DEST_HOST}:${DEST_DIR} ==="
scp "${OUT_ZIM}" "${DEST_HOST}:/tmp/nixos_manual_en_26.11.zim"
ssh "${DEST_HOST}" "sudo mv /tmp/nixos_manual_en_26.11.zim ${DEST_DIR}/nixos_manual_en_26.11.zim && sudo kiwix-manage ${DEST_DIR}/library.xml add ${DEST_DIR}/nixos_manual_en_26.11.zim"

echo "[SUCCESS] NixOS Manual ZIM deployed and live on http://kiwix.home.arpa:8085"
