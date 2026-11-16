#!/run/current-system/sw/bin/bash
# kiwix-update.sh - Automated Kiwix Knowledge Base Synchronizer & Library Manager
# Manages Linux programming, general software engineering, Stack Exchange,
# Wikibooks, and Wikipedia offline knowledge bases on bufflehead.
set -euo pipefail

export PATH="/run/current-system/sw/bin:${PATH:-/usr/bin:/bin}"

KIWIX_DIR="/mnt/wdblack/kiwix"
LIBRARY_XML="${KIWIX_DIR}/library.xml"

DEV_URL="https://lb.download.kiwix.org/zim/devdocs/"
STACK_URL="https://lb.download.kiwix.org/zim/stack_exchange/"
WIKI_URL="https://lb.download.kiwix.org/zim/wikipedia/"
WIKIBOOKS_URL="https://lb.download.kiwix.org/zim/wikibooks/"
WIKIVERSITY_URL="https://lb.download.kiwix.org/zim/wikiversity/"
FREECODECAMP_URL="https://lb.download.kiwix.org/zim/freecodecamp/"
OTHER_URL="https://lb.download.kiwix.org/zim/other/"

log() {
    echo "[$(date '+%Y-%m-%d %H:%M:%S')] $*"
}

mkdir -p "${KIWIX_DIR}"

find_remote_file() {
    local base_url="$1"
    local pattern="$2"
    local remote_file
    remote_file=$(curl -sL "${base_url}" | grep -o -E "${pattern}_[0-9]{4}-[0-9]{2}\.zim" | sort -V | tail -n 1 || true)
    if [ -z "${remote_file}" ]; then
        remote_file=$(curl -sL "${base_url}" | grep -o -E "${pattern}[a-zA-Z0-9_-]*_[0-9]{4}-[0-9]{2}\.zim" | sort -V | tail -n 1 || true)
    fi
    echo "${remote_file}"
}

update_zim_track() {
    local base_url="$1"
    local pattern="$2"
    local desc="$3"

    log "Checking upstream for ${desc} (${pattern})..."
    local remote_file
    remote_file=$(find_remote_file "${base_url}" "${pattern}")

    if [ -z "${remote_file}" ]; then
        log "[WARN] Could not find any upstream files for pattern: ${pattern} at ${base_url}"
        return 0
    fi

    local target_path="${KIWIX_DIR}/${remote_file}"
    if [ -f "${target_path}" ]; then
        log "[UP-TO-DATE] ${remote_file} is already present."
        # Ensure it is indexed in library.xml
        if ! grep -q "${remote_file}" "${LIBRARY_XML}" 2>/dev/null; then
            log "Registering missing index for ${remote_file} into ${LIBRARY_XML}..."
            kiwix-manage "${LIBRARY_XML}" add "${target_path}"
        fi
        return 0
    fi

    log "[UPDATE FOUND] New version available: ${remote_file}"
    local download_url="${base_url}${remote_file}"
    local part_file="${target_path}.part"

    log "Downloading ${download_url}..."
    if ! curl -C - -L --fail --progress-bar "${download_url}" -o "${part_file}"; then
        log "[ERROR] Failed downloading ${download_url}"
        return 1
    fi
    mv "${part_file}" "${target_path}"
    chmod 664 "${target_path}" 2>/dev/null || true

    log "Registering ${remote_file} into ${LIBRARY_XML}..."
    kiwix-manage "${LIBRARY_XML}" add "${target_path}"

    # Prune superseded editions
    for old_file in "${KIWIX_DIR}"/${pattern}*.zim; do
        if [ -f "${old_file}" ] && [ "${old_file}" != "${target_path}" ]; then
            log "Pruning superseded edition: ${old_file}"
            local old_id
            old_id=$(kiwix-manage "${LIBRARY_XML}" show 2>/dev/null | grep -B 1 "${old_file}" | grep "^id:" | awk '{print $2}' || true)
            if [ -n "${old_id}" ]; then
                kiwix-manage "${LIBRARY_XML}" remove "${old_id}" 2>/dev/null || true
            fi
            rm -f "${old_file}"
        fi
    done

    # If full Wikipedia is present, remove the tiny top 100 sample
    if [[ "${pattern}" == "wikipedia_en_all_maxi" && -f "${target_path}" ]]; then
        for top100 in "${KIWIX_DIR}"/wikipedia_en_100*.zim; do
            if [ -f "${top100}" ]; then
                log "Pruning Wikipedia Top 100 sample in favor of full Wikipedia..."
                local top100_id
                top100_id=$(kiwix-manage "${LIBRARY_XML}" show 2>/dev/null | grep -B 1 "${top100}" | grep "^id:" | awk '{print $2}' || true)
                if [ -n "${top100_id}" ]; then
                    kiwix-manage "${LIBRARY_XML}" remove "${top100_id}" 2>/dev/null || true
                fi
                rm -f "${top100}"
            fi
        done
    fi

    return 2 # Signaled that an update occurred
}

sync_devdocs() {
    log "--- Synchronizing DevDocs Documentation & Linux Wikis ---"
    local devdocs=(
        # Linux & Systems Programming
        "devdocs_en_man:Linux man pages"
        "devdocs_en_gnu-make:GNU Make"
        "devdocs_en_gcc:GCC Compiler"
        "devdocs_en_cmake:CMake"
        "devdocs_en_bash:Bash Shell"
        "devdocs_en_zsh:Zsh Shell"
        "devdocs_en_fish:Fish Shell"
        "devdocs_en_git:Git"
        "devdocs_en_nix:Nix Documentation"
        "devdocs_en_docker:Docker"
        "devdocs_en_kubernetes:Kubernetes"
        # Core Languages
        "devdocs_en_c:C Programming"
        "devdocs_en_cpp:C++ Programming"
        "devdocs_en_rust:Rust Programming"
        "devdocs_en_go:Go Programming"
        "devdocs_en_python:Python Programming"
        "devdocs_en_javascript:JavaScript"
        "devdocs_en_typescript:TypeScript"
        "devdocs_en_openjdk:Java OpenJDK"
        "devdocs_en_node:Node.js"
        "devdocs_en_lua:Lua"
        "devdocs_en_zig:Zig"
        "devdocs_en_ruby:Ruby"
        "devdocs_en_php:PHP"
        "devdocs_en_perl:Perl"
        "devdocs_en_haskell:Haskell"
        "devdocs_en_elixir:Elixir"
        "devdocs_en_kotlin:Kotlin"
        # Databases & Networking
        "devdocs_en_sqlite:SQLite"
        "devdocs_en_postgresql:PostgreSQL"
        "devdocs_en_redis:Redis"
        "devdocs_en_nginx:nginx"
        "devdocs_en_jq:jq processor"
        # Web & Frameworks
        "devdocs_en_html:HTML"
        "devdocs_en_css:CSS"
        "devdocs_en_http:HTTP Protocols"
        "devdocs_en_fastapi:FastAPI"
        "devdocs_en_django:Django"
        "devdocs_en_flask:Flask"
    )

    for item in "${devdocs[@]}"; do
        local track="${item%%:*}"
        local desc="${item##*:}"
        update_zim_track "${DEV_URL}" "${track}" "${desc}" || true
    done

    # Distribution Wikis
    update_zim_track "${OTHER_URL}" "archlinux_en_all_maxi" "Arch Linux Wiki" || true
    update_zim_track "${OTHER_URL}" "alpinelinux_en_all_maxi" "Alpine Linux Wiki" || true
    update_zim_track "${OTHER_URL}" "gentoo_en_all_maxi" "Gentoo Linux Wiki" || true
}

sync_stackexchange() {
    log "--- Synchronizing Stack Exchange & Developer Q&A ---"
    local se_tracks=(
        "devops.stackexchange.com_en_all:DevOps Stack Exchange"
        "cs.stackexchange.com_en_all:Computer Science Stack Exchange"
        "softwareengineering.stackexchange.com_en_all:Software Engineering Stack Exchange"
        "codereview.stackexchange.com_en_all:Code Review Stack Exchange"
        "dba.stackexchange.com_en_all:Database Administrators Stack Exchange"
        "unix.stackexchange.com_en_all:Unix and Linux Stack Exchange"
        "serverfault.com_en_all:Server Fault Sysadmin Stack Exchange"
        "askubuntu.com_en_all:Ask Ubuntu Stack Exchange"
        "superuser.com_en_all:Super User Stack Exchange"
    )

    for item in "${se_tracks[@]}"; do
        local track="${item%%:*}"
        local desc="${item##*:}"
        update_zim_track "${STACK_URL}" "${track}" "${desc}" || true
    done
}

sync_books() {
    log "--- Synchronizing Books, Courses & Curricula ---"
    update_zim_track "${FREECODECAMP_URL}" "freecodecamp_en_all" "FreeCodeCamp Complete Curriculum & Rosetta Code" || true
    update_zim_track "${WIKIVERSITY_URL}" "wikiversity_en_all_maxi" "Wikiversity Open Courses & Materials" || true
    update_zim_track "${WIKIBOOKS_URL}" "wikibooks_en_all_maxi" "Wikibooks (Open Computer Science & Programming Books)" || true
}

sync_wiki_simple() {
    log "--- Synchronizing Simple English Wikipedia ---"
    update_zim_track "${WIKI_URL}" "wikipedia_en-simple_all_maxi" "Simple English Wikipedia Maxi" || true
}

sync_stackoverflow() {
    log "--- Synchronizing Full Stack Overflow (107 GB) ---"
    update_zim_track "${STACK_URL}" "stackoverflow.com_en_all" "Stack Overflow Complete Q&A Archive" || true
}

sync_wikipedia() {
    log "--- Synchronizing Full English Wikipedia Maxi (119 GB) ---"
    update_zim_track "${WIKI_URL}" "wikipedia_en_all_maxi" "Wikipedia English Complete Maxi" || true
}

list_library() {
    echo "========================================================"
    echo "=== Downloaded Knowledge Bases in ${KIWIX_DIR} ==="
    echo "========================================================"
    ls -lh "${KIWIX_DIR}"/*.zim 2>/dev/null || echo "No .zim files found."
    echo
    echo "=== Storage Usage on /mnt/wdblack ==="
    df -h "${KIWIX_DIR}"
}

reload_kiwix_serve() {
    log "Checking kiwix-serve status..."
    if command -v systemctl >/dev/null 2>&1; then
        local restart_cmd="systemctl"
        if [ "$(id -u)" -ne 0 ] && command -v sudo >/dev/null 2>&1; then
            restart_cmd="sudo systemctl"
        fi
        if ${restart_cmd} is-active --quiet kiwix-serve 2>/dev/null; then
            ${restart_cmd} restart kiwix-serve 2>/dev/null || true
            log "[SUCCESS] kiwix-serve reloaded and active!"
        fi
    fi
}

main() {
    local target="${1:-all}"

    case "${target}" in
        devdocs)
            sync_devdocs
            reload_kiwix_serve
            ;;
        se|stackexchange)
            sync_stackexchange
            reload_kiwix_serve
            ;;
        books)
            sync_books
            reload_kiwix_serve
            ;;
        wiki-simple)
            sync_wiki_simple
            reload_kiwix_serve
            ;;
        quick)
            sync_devdocs
            sync_stackexchange
            sync_books
            sync_wiki_simple
            reload_kiwix_serve
            ;;
        stackoverflow)
            sync_stackoverflow
            reload_kiwix_serve
            ;;
        wikipedia)
            sync_wikipedia
            reload_kiwix_serve
            ;;
        all)
            log "Starting full Kiwix synchronization (prioritized order)..."
            sync_devdocs
            sync_stackexchange
            sync_books
            sync_wiki_simple
            reload_kiwix_serve
            sync_stackoverflow
            sync_wikipedia
            reload_kiwix_serve
            ;;
        list)
            list_library
            ;;
        *)
            echo "Usage: $0 {devdocs|se|books|wiki-simple|quick|stackoverflow|wikipedia|all|list}"
            exit 1
            ;;
    esac
}

main "$@"
