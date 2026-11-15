#!/usr/bin/env bash
# kiwix-sync.sh - Automated Kiwix knowledge base manager for bufflehead
# Generated with assistance from qwen2.5-coder:14b on YANG

set -eo pipefail

DEST_DIR="/mnt/wdblack/kiwix"
LIBRARY_FILE="$DEST_DIR/library.xml"

# Ensure destination directory exists
mkdir -p "$DEST_DIR"

download_and_add() {
    local url="$1"
    local filename
    filename=$(basename "$url")
    local temp_file="$DEST_DIR/$filename.part"
    local zim_file="$DEST_DIR/$filename"

    if [ -f "$zim_file" ]; then
        echo "[INFO] $filename already exists in $DEST_DIR."
    else
        echo "[INFO] Downloading $filename..."
        echo "[URL]  $url"
        curl -C - -L --progress-bar "$url" -o "$temp_file"
        mv "$temp_file" "$zim_file"
        echo "[OK]   Download complete: $zim_file"
    fi

    echo "[INFO] Registering $filename into $LIBRARY_FILE..."
    if command -v kiwix-manage >/dev/null 2>&1; then
        kiwix-manage "$LIBRARY_FILE" add "$zim_file"
    elif [ -x /run/current-system/sw/bin/kiwix-manage ]; then
        /run/current-system/sw/bin/kiwix-manage "$LIBRARY_FILE" add "$zim_file"
    else
        echo "[ERROR] kiwix-manage binary not found in PATH."
        exit 1
    fi
    echo "[SUCCESS] $filename indexed! Content is live at http://kiwix.home.arpa:8085"
}

list_zims() {
    echo "=== Downloaded Knowledge Bases in $DEST_DIR ==="
    ls -lh "$DEST_DIR"/*.zim 2>/dev/null || echo "No .zim files found."
    echo
    echo "=== Storage Usage on /mnt/wdblack ==="
    df -h "$DEST_DIR"
}

case "$1" in
    nix|devdocs-nix)
        # Official DevDocs Nix Documentation (~10 MB)
        download_and_add "https://lb.download.kiwix.org/zim/devdocs/devdocs_en_nix_2026-10.zim"
        ;;
    wikimed|medicine)
        # Complete English WikiMed with illustrations (~1.86 GB)
        download_and_add "https://lb.download.kiwix.org/zim/wikipedia/wikipedia_en_medicine_maxi_2026-10.zim"
        ;;
    wikimed-mini|medicine-mini)
        # Lightweight WikiMed (~174 MB)
        download_and_add "https://lb.download.kiwix.org/zim/wikipedia/wikipedia_en_medicine_mini_2026-10.zim"
        ;;
    wikipedia-simple)
        # Simple English Wikipedia Maxi (~1.7 GB)
        download_and_add "https://lb.download.kiwix.org/zim/wikipedia/wikipedia_en-simple_all_maxi_2026-09.zim"
        ;;
    wikipedia-top)
        # Wikipedia English Top 100 articles (~30 MB)
        download_and_add "https://lb.download.kiwix.org/zim/wikipedia/wikipedia_en_100_2026-08.zim"
        ;;
    custom)
        if [ -z "$2" ]; then
            echo "Usage: $0 custom <DIRECT_ZIM_URL>"
            exit 1
        fi
        download_and_add "$2"
        ;;
    list)
        list_zims
        ;;
    *)
        echo "Usage: $0 {wikimed|wikimed-mini|wikipedia-simple|wikipedia-top|custom <URL>|list}"
        exit 1
        ;;
esac
