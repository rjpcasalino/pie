#!/usr/bin/env bash
#
# wm-panel - click-on-a-bar-segment dropdown for sway and hyprland.
#
# A bar segment can only be so wide, so each one shows a summary and
# defers the detail to a click. Where that detail appears matters: a
# terminal window is a separate surface that has to be closed again,
# and a TUI that exits on its own (cal, and anything that reads stdin
# until EOF) flickers away before it can be read.
#
# So the detail is shown in a hyprlauncher dropdown instead: it opens
# immediately over the desktop, and Escape closes it. Each segment gets its
# own content, so CPU and memory no longer open the same program.
#
#   --section net|disk|cpu|mem|vol|time|binds  which panel to show (default net)
#   --list                                 print the entries instead of showing
#                                          them; used by the build-time check
#   --dry-run                              print the hyprlauncher command line
#                                          instead of running it
#
# As with status-line.sh, probe failures are normal and must not abort
# anything, so -e is deliberately not set.
set -uo pipefail

: "${WM_C_BG:=#1c1c1c}"
: "${WM_C_FG:=#9e9e9e}"
: "${WM_C_DIM:=#767676}"
: "${WM_C_BLUE:=#5f87af}"
: "${WM_C_CYAN:=#5f8787}"
: "${WM_C_GREEN:=#5faf5f}"
: "${WM_C_YELLOW:=#af875f}"
: "${WM_C_RED:=#af5f5f}"

STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wm-status"
# Deliberately NOT status-line.sh's net_counters file. That one stores
# "rx tx"; this one stores "timestamp rx tx" so a rate can be computed on
# a click without waiting for a second sample. Sharing the file made the
# two scripts alternate formats and the bar's own speed calculation then
# read the timestamp as a byte count.
NET_FILE="$STATE_DIR/net_counters_panel"
NET_WINDOW=2

# Escape anything interpolated into pango markup. An interface name or
# mount point containing & or < would otherwise blank the panel.
esc() {
  case "$1" in
    *'&'* | *'<'* | *'>'*)
      printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
      ;;
    *) printf '%s' "$1" ;;
  esac
}

repeat() {
  local char="$1" count="$2" out=""
  [ "${count:-0}" -gt 0 ] 2>/dev/null || { printf ''; return; }
  while [ "$count" -gt 0 ]; do
    out="$out$char"
    count=$((count - 1))
  done
  printf '%s' "$out"
}

# "  ██████░░░░  42%" - a bar of the given width, coloured by level.
bar() {
  local pct="${1:-0}" width="${2:-20}" filled empty colour
  pct="${pct%%%}"
  case "$pct" in
    '' | *[!0-9.]*) pct=0 ;;
  esac
  pct="${pct%%.*}"

  if [ "$pct" -ge 90 ]; then colour="$WM_C_RED"
  elif [ "$pct" -ge 75 ]; then colour="$WM_C_YELLOW"
  else colour="$WM_C_GREEN"
  fi

  filled=$((pct * width / 100))
  [ "$filled" -gt "$width" ] && filled=$width
  empty=$((width - filled))

  printf '<span foreground="%s">%s</span><span foreground="%s">%s</span> <span foreground="%s">%s%%</span>' \
    "$colour" "$(repeat '█' "$filled")" \
    "$WM_C_DIM" "$(repeat '░' "$empty")" \
    "$colour" "$pct"
}

# Thresholds in one place: green below warn, yellow to crit, red above.
level() {
  local value="$1" warn="$2" crit="$3" dim="$4" text="$5" colour
  case "$value" in
    '' | *[!0-9.]*) colour="$dim" ;;
    *)
      if [ "$value" -ge "$crit" ] 2>/dev/null; then colour="$WM_C_RED"
      elif [ "$value" -ge "$warn" ] 2>/dev/null; then colour="$WM_C_YELLOW"
      else colour="$WM_C_GREEN"
      fi
      ;;
  esac
  printf '<span foreground="%s">%s</span>' "$colour" "$(esc "$text")"
}

# Bold label, used for the small headings inside a panel.
span() {
  printf '<span foreground="%s">%s</span>' "$1" "$(esc "${2:-}")"
}

human_kib() {
  local kib="${1:-0}"
  if [ "${kib:-0}" -gt 1048576 ] 2>/dev/null; then
    printf '%d.%dG' $((kib / 1048576)) $(((kib % 1048576) * 10 / 1048576))
  elif [ "${kib:-0}" -gt 1024 ] 2>/dev/null; then
    printf '%d.%dM' $((kib / 1024)) $(((kib % 1024) * 10 / 1024))
  else
    printf '%dK' "$kib"
  fi
}

# ---------------------------------------------------------------------
# Panels
# ---------------------------------------------------------------------

panel_net() {
  printf '<span foreground="%s" size="large">Network</span>\n' "$WM_C_BLUE"

  local route
  route=$(ip route get 1.1.1.1 2>/dev/null | awk '{print $5; exit}')
  if [ -z "$route" ]; then
    printf '<span foreground="%s">  no route to the internet</span>\n' "$WM_C_DIM"
  else
    printf '  via <span foreground="%s">%s</span>\n' "$WM_C_CYAN" "$(esc "$route")"
  fi

  printf '\n'
  printf '  %s\n' "$(span "$WM_C_DIM" 'interfaces')"
  ip -o addr show 2>/dev/null |
    grep -v ' state DOWN' | awk '$2 != "lo" {print $2}' | sort -u |
    while read -r dev; do
      [ -n "$dev" ] || continue
      local ipv4 state mtu
      ipv4=$(ip -4 -o addr show dev "$dev" 2>/dev/null |
        awk '{split($4, a, "/"); print a[1]; exit}')
      state=$(cat "/sys/class/net/$dev/operstate" 2>/dev/null)
      mtu=$(cat "/sys/class/net/$dev/mtu" 2>/dev/null)
      local colour="$WM_C_GREEN"
      [ "$state" = "up" ] || colour="$WM_C_DIM"
      printf '    %s %s %s\n' \
        "$(span "$colour" "$(printf '%-10s' "$(esc "$dev")")")" \
        "$(esc "${ipv4:-no IPv4}")" \
        "$(span "$WM_C_DIM" "${state:-?}${mtu:+, mtu $mtu}")"
    done

  printf '\n'
  printf '  %s\n' "$(span "$WM_C_DIM" 'throughput')"
  local total=0
  if [ -n "$route" ] && [ -r "/sys/class/net/$route/statistics/rx_bytes" ]; then
    local now prev
    now=$(date +%s)
    local rx tx
    rx=$(cat "/sys/class/net/$route/statistics/rx_bytes" 2>/dev/null)
    tx=$(cat "/sys/class/net/$route/statistics/tx_bytes" 2>/dev/null)
    if [ -r "$NET_FILE" ]; then
      local pnow prx ptx
      read -r pnow prx ptx <"$NET_FILE" 2>/dev/null || :
      if [ -n "${pnow:-}" ] && [ "${now}" -gt "${pnow}" ] 2>/dev/null; then
        local dt=$((now - pnow))
        [ "$dt" -gt 0 ] || dt=1
        # rx_bytes/tx_bytes are bytes, so the delta over dt is bytes per
        # second. human_kib formats KiB, and is shared with the memory
        # panel where the input really is KiB, so convert here: divide by
        # dt * 1024 to get KiB/s. Same arithmetic as status-line.sh, which
        # divides by POLL_INTERVAL * 1024.
        printf '    %s  %s\n' \
          "$(span "$WM_C_DIM" 'recv')" \
          "$(span "$WM_C_GREEN" "$(human_kib $(((rx - prx) / (dt * 1024))))/s")"
        printf '    %s  %s\n' \
          "$(span "$WM_C_DIM" 'send')" \
          "$(span "$WM_C_BLUE" "$(human_kib $(((tx - ptx) / (dt * 1024))))/s")"
        total=1
      fi
    fi
    mkdir -p "$STATE_DIR" 2>/dev/null
    printf '%s %s %s' "$now" "$rx" "$tx" >"$NET_FILE" 2>/dev/null
  fi
  [ "$total" = "1" ] ||
    printf '    <span foreground="%s">sampling, click again for a rate</span>\n' "$WM_C_DIM"

  printf '\n'
  printf '  %s %s\n' "$(span "$WM_C_DIM" 'established:')" \
    "$(span "$WM_C_FG" "$(ss -tua state established 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')")"
  printf '  %s %s\n' "$(span "$WM_C_DIM" 'listening:')" \
    "$(span "$WM_C_FG" "$(ss -tul state listening 2>/dev/null | tail -n +2 | wc -l | tr -d ' ')")"
}

panel_disk() {
  printf '<span foreground="%s" size="large">Storage</span>\n' "$WM_C_YELLOW"
  printf '\n'

  df -h --output=target,pcent,size,used,avail \
    -x tmpfs -x devtmpfs -x squashfs -x overlay -x efivarfs 2>/dev/null |
    tail -n +2 | while read -r target pcent size used avail; do
      [ -n "$target" ] || continue
      printf '  %s\n' "$(span "$WM_C_FG" "$target")"
      printf '    %s  %s\n' "$(bar "$pcent")" \
        "$(span "$WM_C_DIM" "$used of $size used, $avail free")"
      printf '\n'
    done

  # Largest subdirectories, so the panel answers "what is filling this
  # up" rather than restating the df line the bar already shows.
  local top_home="${HOME:-/tmp}"
  if command -v dust >/dev/null 2>&1; then
    printf '  %s\n' "$(span "$WM_C_DIM" 'largest in home:')"
    dust -d 1 -n 6 -b -r "$top_home" 2>/dev/null |
      head -n 8 | while read -r line; do
        [ -n "$line" ] && printf '    <span foreground="%s">%s</span>\n' "$WM_C_FG" "$(esc "$line")"
      done
  fi
}

panel_cpu() {
  printf '<span foreground="%s" size="large">CPU</span>\n' "$WM_C_GREEN"

  local usage cores
  usage=$(top -bn1 2>/dev/null | grep -E 'Cpu\(s\)|%Cpu' | head -n1 |
    awk '{
      for (i = 2; i <= NF; i++) {
        v = ""
        if ($i ~ /^id,$/) v = $(i - 1)
        else if ($i == "id" || $i == "%id") v = $(i + 1)
        if (v != "") { g = v; gsub(/[^0-9.]/, "", g)
          if (g != "") { print int(100 - g); exit } }
      }
    }')
  usage="${usage:-0}"
  cores=$(grep -c ^processor /proc/cpuinfo 2>/dev/null)
  cores="${cores:-?}"

  printf '  %s\n' "$(span "$WM_C_FG" "$usage% of $cores cores")"
  printf '  %s\n\n' "$(bar "$usage")"

  local load
  load=$(awk '{print $1" "$2" "$3}' /proc/loadavg 2>/dev/null)
  printf '  %s %s\n' "$(span "$WM_C_DIM" 'load:')" "$(span "$WM_C_FG" "$load")"

  local temp
  for zone in /sys/class/thermal/thermal_zone*/temp; do
    [ -r "$zone" ] || continue
    temp=$(( $(cat "$zone") / 1000 ))
    break
  done
  [ -n "${temp:-}" ] && printf '  %s %s\n' "$(span "$WM_C_DIM" 'temp:')" \
    "$(level "$temp" 65 80 "$WM_C_DIM" "${temp}°C")"

  printf '\n  %s\n' "$(span "$WM_C_DIM" 'busiest processes')"
  ps -eo pcpu,rss,comm --sort=-pcpu 2>/dev/null | head -n 8 |
    tail -n +2 | while read -r pcpu rss comm; do
      [ -n "${comm:-}" ] || continue
      printf '    <span foreground="%s">%5s%%</span>  %s  %s\n' \
        "$WM_C_GREEN" "$pcpu" \
        "$(span "$WM_C_FG" "$comm")" \
        "$(span "$WM_C_DIM" "$(human_kib "$rss")")"
    done
}

panel_mem() {
  printf '<span foreground="%s" size="large">Memory</span>\n' "$WM_C_BLUE"

  local total used avail pct
  read -r total used avail pct <<<"$(free -h | awk '/^Mem:/ {
    t = $2; u = $3; a = $7; sub(/G$/, "", t); sub(/G$/, "", u); sub(/G$/, "", a)
    p = $2 + 0 ? (u / t) * 100 : 0
    printf "%d %d %d %d", t, u, a, p
  }')"
  total="${total:-0}"; used="${used:-0}"; avail="${avail:-0}"; pct="${pct:-0}"

  printf '  %s\n' "$(span "$WM_C_FG" "${used}G of ${total}G used")"
  printf '  %s\n\n' "$(bar "$pct")"

  printf '  %s %s\n' "$(span "$WM_C_DIM" 'free:')" \
    "$(span "$WM_C_FG" "${avail}G available")"

  local swap
  read -r swap <<<"$(free -h | awk '/^Swap:/ {s = $2; sub(/G$/, "", s); print s + 0}')"
  printf '  %s %s\n' "$(span "$WM_C_DIM" 'swap:')" \
    "$(span "$WM_C_FG" "${swap:-0}G swap")"

  local bat
  for d in /sys/class/power_supply/BAT*; do
    [ -d "$d" ] || continue
    bat="$(cat "$d/capacity" 2>/dev/null)% $(cat "$d/status" 2>/dev/null)"
    break
  done
  [ -n "${bat:-}" ] && printf '  %s %s\n' \
    "$(span "$WM_C_DIM" 'battery:')" "$(span "$WM_C_YELLOW" "$bat")"

  printf '\n  %s\n' "$(span "$WM_C_DIM" 'largest processes')"
  ps -eo pcpu,rss,comm --sort=-rss 2>/dev/null | head -n 8 |
    tail -n +2 | while read -r pcpu rss comm; do
      [ -n "${comm:-}" ] || continue
      printf '    %s  %s\n' \
        "$(span "$WM_C_FG" "$comm")" \
        "$(span "$WM_C_YELLOW" "$(human_kib "$rss")")"
    done
}

panel_vol() {
  printf '<span foreground="%s" size="large">Audio Output</span>\n' "$WM_C_CYAN"

  local vol_raw vol_pct
  vol_raw=$(wpctl get-volume @DEFAULT_AUDIO_SINK@ 2>/dev/null || true)
  if [ -n "$vol_raw" ]; then
    vol_pct=$(printf '%s' "$vol_raw" | awk '{print int($2 * 100)}')
    if [[ "$vol_raw" == *"[MUTED]"* ]]; then
      printf '  %s %s\n' "$(span "$WM_C_DIM" 'volume:')" "$(span "$WM_C_RED" "${vol_pct}% (MUTED)")"
    else
      printf '  %s %s\n' "$(span "$WM_C_DIM" 'volume:')" "$(span "$WM_C_FG" "${vol_pct}%")"
    fi
    printf '  %s\n' "$(bar "${vol_pct:-0}")"
  else
    printf '  <span foreground="%s">no active audio sink</span>\n' "$WM_C_DIM"
  fi

  printf '\n  %s\n' "$(span "$WM_C_DIM" 'select output sink (Enter to switch)')"
  local sinks_found=0
  local line
  while IFS= read -r line; do
    [ -n "$line" ] || continue
    sinks_found=1
    local is_def=" "
    case "$line" in
      *"*"*) is_def="*" ;;
    esac
    local rest="${line#*"*"}"
    [ "$rest" = "$line" ] && rest="$line"
    rest=$(printf '%s' "$rest" | sed -e 's/^[[:space:]│├─└]*//')
    local id="${rest%%.*}"
    local after_id="${rest#*. }"
    local name="${after_id% \[vol:*}"
    name=$(printf '%s' "$name" | sed -e 's/[[:space:]]*$//')
    local vol=""
    case "$after_id" in
      *"[vol:"*)
        vol="${after_id##*\[vol: }"
        vol="${vol%\]*}"
        vol=$(printf '%s' "$vol" | awk '{printf "%d%%", int($1 * 100)}')
        ;;
    esac

    local label="$name"
    local node_name
    node_name=$(wpctl inspect "$id" 2>/dev/null | awk -F'"' '/node\.name/ {print $2; exit}')
    case "${node_name:-$name}" in
      *usb*|*"USB Composite"*) label="USB Speakers ($name)" ;;
      *bluez*)                 label="Bluetooth ($name)" ;;
      *pci*|*"Starship"*)      label="Receiver — Mini-Jack ($name)" ;;
    esac

    if [ "$is_def" = "*" ]; then
      printf '    <span foreground="%s">● [%s] %s</span> %s\n' \
        "$WM_C_GREEN" "$id" "$(esc "$label")" "$(span "$WM_C_DIM" "${vol} [active]")"
    else
      printf '    <span foreground="%s">○ [%s] %s</span> %s\n' \
        "$WM_C_FG" "$id" "$(esc "$label")" "$(span "$WM_C_DIM" "${vol}")"
    fi
  done < <(wpctl status 2>/dev/null | awk '
    /^Audio/ { in_audio=1; next }
    /^(Video|Settings)/ { in_audio=0 }
    in_audio && /Sinks:/ { in_sinks=1; next }
    in_audio && in_sinks && /(Sources:|Filters:|Streams:)/ { in_sinks=0 }
    in_audio && in_sinks && /[0-9]+\./ { print }
  ')

  if [ "$sinks_found" = "0" ]; then
    printf '    <span foreground="%s">no PipeWire sinks detected</span>\n' "$WM_C_DIM"
  fi

  printf '\n  %s\n' "$(span "$WM_C_DIM" 'quick actions')"
  printf '    <span foreground="%s">⇄  Toggle USB Speakers ↔ Receiver</span>\n' "$WM_C_CYAN"
  printf '    <span foreground="%s">🔇 Toggle Mute</span>\n' "$WM_C_YELLOW"
  printf '    <span foreground="%s">  Bluetooth Console (bluetoothctl)</span>\n' "$WM_C_BLUE"
}

panel_time() {
  printf '<span foreground="%s" size="large">%s</span>\n' "$WM_C_FG" "$(date +'%A, %d %B %Y %I:%M:%S %p')"

  if command -v cal >/dev/null 2>&1; then
    cal 2>/dev/null | while read -r line; do
      [ -n "$line" ] && printf '  <span foreground="%s">%s</span>\n' "$WM_C_CYAN" "$(esc "$line")"
    done
  fi

  printf '\n'
  printf '  %s %s\n' "$(span "$WM_C_DIM" 'uptime:')" \
    "$(span "$WM_C_FG" "$(awk '{m = int($1/60); h = int(m/60); d = int(h/24)
       printf "%dd %dh %dm", d, h%24, m%60}' /proc/uptime 2>/dev/null)")"
  printf '  %s %s\n' "$(span "$WM_C_DIM" 'kernel:')" \
    "$(span "$WM_C_FG" "$(uname -r 2>/dev/null)")"
  printf '  %s %s\n' "$(span "$WM_C_DIM" 'shell: ')" \
    "$(span "$WM_C_FG" "${SHELL##*/}")"
}

bind_row() {
  local key="$1" desc="$2"
  printf '  <tt><span foreground="%s">%-24s</span></tt> <span foreground="%s">%s</span>\n' \
    "$WM_C_CYAN" "$(esc "$key")" \
    "$WM_C_FG" "$(esc "$desc")"
}

bind_hdr() {
  printf '<span foreground="%s" weight="bold">── %s ──</span>\n' "$WM_C_BLUE" "$(esc "$1")"
}

panel_binds() {
  bind_hdr "Launchers & Menus"
  bind_row "SUPER + Return"         "Open terminal (foot)"
  bind_row "SUPER + Space / D"      "Toggle app launcher (hyprlauncher)"
  bind_row "SUPER + ALT + Space"    "Open math / calc finder (hyprlauncher)"
  bind_row "SUPER + /"              "Show this keybindings cheat sheet"

  bind_hdr "TUI Utilities"
  bind_row "SUPER + CTRL + Return"  "Launch tmux session"
  bind_row "SUPER + CTRL + T"       "Launch btop system monitor"
  bind_row "SUPER + SHIFT + F"      "Launch yazi file manager"
  bind_row "SUPER + SHIFT + D"      "Launch lazydocker"
  bind_row "SUPER + SHIFT + ALT + M" "Launch cliamp music player"
  bind_row "SUPER + CTRL + W"       "Network status (networkctl)"
  bind_row "SUPER + CTRL + B"       "Bluetooth console (bluetoothctl)"

  bind_hdr "Window Management"
  bind_row "SUPER + Q / W / X"      "Close active window"
  bind_row "SUPER + SHIFT + Q"      "Close active window"
  bind_row "SUPER + T"              "Toggle floating window"
  bind_row "SUPER + SHIFT + Space"  "Toggle floating window"
  bind_row "SUPER + F"              "Toggle fullscreen"
  bind_row "SUPER + ALT + F"        "Toggle maximize (keep bar/gaps)"
  bind_row "SUPER + CTRL + F"       "Force internal + client fullscreen"
  bind_row "SUPER + O"              "Pin floating window on all workspaces"
  bind_row "SUPER + Left-Drag"      "Move window with mouse"
  bind_row "SUPER + Right-Drag"     "Resize window with mouse"

  bind_hdr "Focus & Swap"
  bind_row "SUPER + H / J / K / L"  "Focus window left / down / up / right"
  bind_row "SUPER + Arrow Keys"     "Focus window left / down / up / right"
  bind_row "SUPER + SHIFT + H/J/K/L" "Swap window left / down / up / right"
  bind_row "SUPER + SHIFT + ← / →"  "Swap window left / right"

  bind_hdr "Groups (Tabbed Windows)"
  bind_row "SUPER + G"              "Toggle window group (tabs)"
  bind_row "SUPER + ALT + G"        "Move active window out of group"
  bind_row "SUPER + CTRL + ← / →"   "Switch to prev / next window in group"

  bind_hdr "Workspaces"
  bind_row "SUPER + 1..9, 0"        "Switch to workspace 1..10"
  bind_row "SUPER + SHIFT + 1..9, 0" "Move window to workspace 1..10 & follow"
  bind_row "SUPER + ALT + 1..9, 0"  "Send window to workspace 1..10 silently"

  bind_hdr "System, Appearance & Media"
  bind_row "SUPER + A"              "GTK & cursor theme settings (nwg-look)"
  bind_row "SUPER + C"              "Reset cursor to stock blue Hyprland arrow"
  bind_row "SUPER + SHIFT + S"      "Region screenshot to ~/Pictures & clipboard"
  bind_row "Print"                  "Region screenshot to ~/Pictures & clipboard"
  bind_row "SUPER + ALT + L"        "Lock screen (hyprlock)"
  bind_row "CTRL + ALT + Delete"    "Exit Hyprland session"
  bind_row "SUPER + V"              "Audio output switcher / volume panel"
  bind_row "SUPER + SHIFT + V"      "Toggle USB Speakers ↔ Receiver"
  bind_row "XF86AudioRaise/Lower"   "Volume +5% / -5% (wpctl)"
  bind_row "XF86AudioMute"          "Toggle audio mute"
  bind_row "XF86AudioPlay/Next/Prev" "Media play-pause / next / previous"
  bind_row "XF86MonBrightnessUp/Dn" "Screen brightness +5% / -5%"
}

# ---------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------
SECTION=net
LIST_ONLY=0
DRY_RUN=0

while [ $# -gt 0 ]; do
  case "$1" in
    --section)
      [ $# -ge 2 ] || { printf 'wm-panel: --section requires an argument\n' >&2; exit 2; }
      shift
      SECTION="$1"
      ;;
    --list) LIST_ONLY=1 ;;
    --dry-run) DRY_RUN=1 ;;
    -h | --help)
      printf 'usage: %s [--section net|disk|cpu|mem|vol|time|binds] [--list] [--dry-run]\n' \
        "$(basename "$0")"
      exit 0
      ;;
    *)
      printf 'wm-panel: unknown option %s\n' "$1" >&2
      exit 2
      ;;
  esac
  shift
done

render_panel() {
  case "$SECTION" in
    net) panel_net ;;
    disk) panel_disk ;;
    cpu) panel_cpu ;;
    mem) panel_mem ;;
    vol) panel_vol ;;
    time) panel_time ;;
    binds) panel_binds ;;
    *)
      printf 'wm-panel: unknown section %s\n' "$SECTION" >&2
      exit 2
      ;;
  esac
}

# Rendered once, up front. The content is captured rather than streamed
# so it can be fed to hyprlauncher below: hyprlauncher in dmenu mode
# reads its list on stdin (filtering out empty lines so every entry
# renders as a clean row).
PANEL_CONTENT=$(render_panel | awk 'NF > 0')

if [ "$LIST_ONLY" = "1" ]; then
  printf '%s\n' "$PANEL_CONTENT"
  exit 0
fi

# ---------------------------------------------------------------------
# Presentation
#
# hyprlauncher in dmenu mode (-m / --dmenu) sends the newline-separated
# entries over hyprwire IPC to the running hyprlauncher daemon (or opens
# directly if no daemon is running), rendering Pango markup natively via
# hyprtoolkit.
# ---------------------------------------------------------------------
LAUNCHER="${WM_PANEL_LAUNCHER:-hyprlauncher}"

if ! [ -x "$LAUNCHER" ] && ! command -v "$LAUNCHER" >/dev/null 2>&1; then
  printf 'wm-panel: hyprlauncher not found at %s\n' "$LAUNCHER" >&2
  exit 127
fi

if [ "$DRY_RUN" = "1" ]; then
  printf '%s --dmenu\n' "$LAUNCHER"
  exit 0
fi

run_bind_selection() {
  local sel="$1"
  [ -n "$sel" ] || return 0
  case "$sel" in
    *"Open terminal (foot)"*)               exec foot ;;
    *"Toggle app launcher"*)                exec hyprlauncher -t ;;
    *"Open math / calc finder"*)            exec hyprlauncher -f math ;;
    *"Launch tmux session"*)                exec foot -e tmux ;;
    *"Launch btop system monitor"*)         exec foot -e btop ;;
    *"Launch yazi file manager"*)           exec foot -e yazi ;;
    *"Launch lazydocker"*)                  exec foot -e lazydocker ;;
    *"Launch cliamp music player"*)         exec foot -e cliamp ;;
    *"Network status (networkctl)"*)        exec foot -e sh -c 'networkctl status; read -r -p "Press Enter to close..."' ;;
    *"Bluetooth console (bluetoothctl)"*)   exec foot -e bluetoothctl ;;
    *"Close active window"*)                exec hyprctl dispatch 'hl.dsp.window.close()' ;;
    *"Toggle floating window"*)             exec hyprctl dispatch 'hl.dsp.window.float({ action = "toggle" })' ;;
    *"Toggle fullscreen"*)                  exec hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "fullscreen", action = "toggle" })' ;;
    *"Toggle maximize"*)                    exec hyprctl dispatch 'hl.dsp.window.fullscreen({ mode = "maximized", action = "toggle" })' ;;
    *"Force internal + client fullscreen"*) exec hyprctl dispatch 'hl.dsp.window.fullscreen_state({ action = "set", internal = 1, client = 1 })' ;;
    *"Pin floating window"*)                exec hyprctl dispatch 'hl.dsp.window.pin({ action = "toggle" })' ;;
    *"Toggle window group (tabs)"*)         exec hyprctl dispatch 'hl.dsp.group.toggle()' ;;
    *"Move active window out of group"*)    exec hyprctl dispatch 'hl.dsp.window.move({ out_of_group = true })' ;;
    *"GTK &amp; cursor theme settings"*|*"GTK & cursor theme settings"*) exec nwg-look ;;
    *"Region screenshot"*)                  exec bash -c 'FILE=~/Pictures/Screenshot_$(date +%Y%m%d_%H%M%S).png; grim -g "$(slurp)" "$FILE" && wl-copy < "$FILE"' ;;
    *"Lock screen (hyprlock)"*)             exec hyprlock ;;
    *"Exit Hyprland session"*)              exec hyprctl dispatch 'hl.dsp.exit()' ;;
    *"Audio output switcher"*)              exec "$0" --section vol ;;
    *"Toggle USB Speakers"*)                exec audio-switch toggle ;;
    *"Toggle audio mute"*)                  exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle ;;
    *"Media play-pause"*)                   exec playerctl play-pause ;;
  esac
}

run_vol_selection() {
  local sel="$1"
  [ -n "$sel" ] || return 0
  case "$sel" in
    *"["*"]"*)
      local id
      id=$(printf '%s' "$sel" | sed -n 's/.*\[\([0-9][0-9]*\)\].*/\1/p')
      if [ -n "$id" ]; then
        exec wpctl set-default "$id"
      fi
      ;;
    *"Toggle USB Speakers"*)
      exec audio-switch toggle
      ;;
    *"Toggle Mute"*)
      exec wpctl set-mute @DEFAULT_AUDIO_SINK@ toggle
      ;;
    *"Bluetooth Console"*)
      exec foot -e bluetoothctl
      ;;
  esac
}

mkdir -p "$STATE_DIR" 2>/dev/null
SELECTED=$(printf '%s\n' "$PANEL_CONTENT" | "$LAUNCHER" --dmenu)
STATUS=$?
if [ "$STATUS" -eq 0 ] && [ -n "$SELECTED" ]; then
  case "$SECTION" in
    binds) run_bind_selection "$SELECTED" ;;
    vol)   run_vol_selection "$SELECTED" ;;
  esac
fi
exit "$STATUS"
