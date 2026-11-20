#!/usr/bin/env bash
#
# wm-status - shared status line for sway and hyprland (waybar)
#
# Runs the same collection logic for both compositors:
#   --watch                  emit every 2s forever (sway `status_command`)
#   --once                   emit one line and exit (waybar polling)
#   --section net|disk|...   emit a single segment, so a waybar module
#                            can own one part of the bar and give it its
#                            own click and scroll handlers
#   --plain                  strip colour markup, for debugging
#
# State that must survive between iterations lives under
# $XDG_RUNTIME_DIR/wm-status rather than in-process, because the waybar
# consumer is short-lived and re-executes this script on every tick.

# Probe failures (an absent battery, a down interface, ss returning
# nothing) are normal and must never abort the bar, so -e is
# deliberately not set. -u and -o pipefail still catch real mistakes.
set -uo pipefail

# Overridden by the Nix wrapper. Standalone defaults match the Habamax
# palette used by the console and both bars.
: "${WM_C_BG:=#1c1c1c}"
: "${WM_C_FG:=#9e9e9e}"
: "${WM_C_DIM:=#767676}"
: "${WM_C_BLUE:=#5f87af}"
: "${WM_C_CYAN:=#5f8787}"
: "${WM_C_GREEN:=#5faf5f}"
: "${WM_C_YELLOW:=#af875f}"
: "${WM_C_RED:=#af5f5f}"
: "${WM_C_MAGENTA:=#af87af}"

readonly POLL_INTERVAL=2
readonly PUB_IP_MAX_AGE=60

STATE_DIR="${XDG_RUNTIME_DIR:-/run/user/$(id -u)}/wm-status"
PUB_IP_FILE="$STATE_DIR/pub_ip"
PUB_IP_STAMP="$STATE_DIR/pub_ip_stamp"

# Escape data that is interpolated into pango markup. Without this a
# mount point or interface name containing & or < would render as a
# markup error and blank the segment.
pango_escape() {
  case "$1" in
    *'&'* | *'<'* | *'>'*)
      printf '%s' "$1" | sed -e 's/&/\&amp;/g' -e 's/</\&lt;/g' -e 's/>/\&gt;/g'
      ;;
    *) printf '%s' "$1" ;;
  esac
}

# span COLOR TEXT - a coloured pango span, or bare TEXT when colouring
# is off.
span() {
  if [ "$PLAIN" = "1" ]; then
    printf '%s' "$2"
  else
    printf '<span foreground="%s">%s</span>' "$1" "$(pango_escape "$2")"
  fi
}

# ---------------------------------------------------------------------
# Public IP - cached, refreshed out of band so the bar never blocks on
# a network round trip.
# ---------------------------------------------------------------------
fetch_pub_ip() {
  mkdir -p "$STATE_DIR" 2>/dev/null
  local ip
  ip=$(curl -s --max-time 2 https://ifconfig.me 2>/dev/null) || ip=""
  [ -n "$ip" ] || ip="offline"
  printf '%s' "$ip" >"$PUB_IP_FILE" 2>/dev/null
  date +%s >"$PUB_IP_STAMP" 2>/dev/null
}

read_pub_ip() {
  local stamp now age
  stamp=$(cat "$PUB_IP_STAMP" 2>/dev/null) || stamp=0
  now=$(date +%s)
  age=$((now - ${stamp:-0}))

  if [ "$age" -gt "$PUB_IP_MAX_AGE" ]; then
    if [ "$age" -gt $((PUB_IP_MAX_AGE * 4)) ]; then
      # Never fetched, or stale beyond recovery - kick one off now.
      fetch_pub_ip &
      printf 'fetching...'
      return
    fi
  fi

  if [ -s "$PUB_IP_FILE" ]; then
    cat "$PUB_IP_FILE"
  else
    printf 'fetching...'
  fi
}

# ---------------------------------------------------------------------
# Collection
# ---------------------------------------------------------------------
collect() {
  # --- network ---
  IFACES_ACTIVE=$(ip -o -4 addr show 2>/dev/null |
    grep -v ' state DOWN' | awk '$2 != "lo" {print $2 ":" $4}' |
    cut -d'/' -f1 | tr '\n' ' ' | sed 's/ $//')

  PUB=$(read_pub_ip)

  VPN=$(ip link show 2>/dev/null |
    grep -E 'wg|tun|mullvad|proton' | awk -F': ' '{print $2}' | head -n1)

  # --- disk ---
  DISKS=$(df -h --output=target,pcent -x tmpfs -x devtmpfs -x squashfs \
    -x overlay -x efivarfs 2>/dev/null |
    tail -n +2 | awk '{printf "%s:%s ", $1, $2}' | sed 's/ $//')

  # --- cpu / load / temp ---
  LOAD=$(awk '{print $1" "$2" "$3}' /proc/loadavg)
  CPU_RAW=$(top -bn1 2>/dev/null | grep -E 'Cpu\(s\)|%Cpu' | head -n1)
  # procps has shipped both "97.7 id," (value before label, label keeps its
  # trailing comma) and "id 97.7" layouts, so pick the neighbour based on
  # which form the label is in rather than assuming a fixed column.
  CPU=$(printf '%s' "$CPU_RAW" | awk '
    NF {
      for (i = 2; i <= NF; i++) {
        v = ""
        if ($i ~ /^id,$/)      v = $(i - 1)
        else if ($i == "id" || $i == "%id") v = $(i + 1)
        if (v != "") {
          g = v; gsub(/[^0-9.]/, "", g)
          if (g != "") { print int(100 - g) "%"; exit }
        }
      }
    }')
  [ -n "$CPU" ] || CPU="N/A"

  TEMP=""
  TEMP_C=""
  for zone in /sys/class/thermal/thermal_zone*/temp; do
    [ -r "$zone" ] || continue
    TEMP_C=$(( $(cat "$zone") / 1000 ))
    break
  done
  if [ -n "$TEMP_C" ]; then
    # Escalate colour with temperature so a hot machine reads at a glance.
    if [ "$TEMP_C" -ge 80 ]; then
      TEMP=$(span "$WM_C_RED" " (${TEMP_C}°C)")
    elif [ "$TEMP_C" -ge 65 ]; then
      TEMP=$(span "$WM_C_YELLOW" " (${TEMP_C}°C)")
    else
      TEMP=$(span "$WM_C_CYAN" " (${TEMP_C}°C)")
    fi
  fi

  # --- memory ---
  MEM=$(free -h | awk '/^Mem:/ {print $3 "/" $2}')

  # --- battery ---
  BAT_STR=""
  BAT_DIR=""
  for d in /sys/class/power_supply/BAT*; do
    [ -d "$d" ] || continue
    BAT_DIR="$d"
    break
  done
  if [ -n "$BAT_DIR" ]; then
    BAT_CAP=$(cat "$BAT_DIR/capacity" 2>/dev/null)
    BAT_STAT=$(cat "$BAT_DIR/status" 2>/dev/null)
    if [ "$BAT_STAT" = "Charging" ]; then
      BAT_STR=$(span "$WM_C_GREEN" " ⚡ ${BAT_CAP}%")
    else
      BAT_STR=$(span "$WM_C_YELLOW" " 🔋 ${BAT_CAP}%")
    fi
  fi

  # --- volume ---
  VOL_RAW=$(wpctl get-volume @DEFAULT_SINK@ 2>/dev/null)
  if [ -n "$VOL_RAW" ]; then
    VOL_PCT=$(printf '%s' "$VOL_RAW" | awk '{print int($2 * 100)"%"}')
    SINK_NAME=$(wpctl inspect @DEFAULT_SINK@ 2>/dev/null | awk -F'"' '/node\.name/ {print $2; exit}')
    case "${SINK_NAME:-}" in
      *usb*)   SINK_TAG=" [USB]" ;;
      *bluez*) SINK_TAG=" [BT]" ;;
      *pci*)   SINK_TAG=" [RCV]" ;;
      *)       SINK_TAG="" ;;
    esac
    if [[ "$VOL_RAW" == *"[MUTED]"* ]]; then
      VOL=$(span "$WM_C_RED" "${VOL_PCT}${SINK_TAG} (MUTED)")
    else
      VOL=$(span "$WM_C_FG" "${VOL_PCT}${SINK_TAG}")
    fi
  else
    VOL=$(span "$WM_C_DIM" "N/A")
  fi

  # --- uptime & date ---
  UPTIME=$(awk '{
    m = int($1 / 60); h = int(m / 60); d = int(h / 24)
    printf "%sd %sh %sm", d, h % 24, m % 60
  }' /proc/uptime)
  UPTIME=$(printf '%s' "$UPTIME" | sed 's/^0d //; s/^0h //')
  DATE=$(date +'%a %Y-%m-%d %H:%M:%S')
}

# ---------------------------------------------------------------------
# Rendering
#
# Each piece of the line is built into its own variable so that a
# consumer can show all of them (sway) or just one (a single waybar
# module, which is what gives each segment its own click handler).
# ---------------------------------------------------------------------
render() {
  case "$SECTION" in
    net) printf '%s\n' "$SEG_net" ;;
    disk) printf '%s\n' "$SEG_disk" ;;
    cpu) printf '%s\n' "$SEG_cpu" ;;
    mem) printf '%s\n' "$SEG_mem" ;;
    vol) printf '%s\n' "$SEG_vol" ;;
    time) printf '%s\n' "$SEG_time" ;;
    *)
      printf '%s | %s | %s | %s | %s | %s\n' \
        "$SEG_net" "$SEG_disk" "$SEG_cpu" "$SEG_mem" "$SEG_vol" "$SEG_time"
      ;;
  esac
}

build_segments() {
  SEG_net=$'\U1F1FA\U1F1F8'" IF: [ $(span "$WM_C_CYAN" "$IFACES_ACTIVE") ]"
  SEG_net+=" | PUB: $(span "$WM_C_FG" "$PUB")"
  [ -n "$VPN" ] && SEG_net+="$(span "$WM_C_MAGENTA" " | 🛡️ $VPN")"

  SEG_disk="DISK: [ $(span "$WM_C_YELLOW" "$DISKS") ]"

  SEG_cpu="CPU: $(span "$WM_C_GREEN" "$CPU")"
  SEG_cpu+="$TEMP (load $(span "$WM_C_DIM" "$LOAD"))"

  SEG_mem="RAM: $(span "$WM_C_BLUE" "$MEM")"
  [ -n "$BAT_STR" ] && SEG_mem+="$BAT_STR"

  SEG_vol="VOL: $VOL"

  SEG_time="UP: $(span "$WM_C_DIM" "$UPTIME") | $(span "$WM_C_FG" "$DATE")"
}

# ---------------------------------------------------------------------
# Entry point
# ---------------------------------------------------------------------
PLAIN=0
MODE=once
SECTION=""

while [ $# -gt 0 ]; do
  case "$1" in
    --watch) MODE=watch ;;
    --once) MODE=once ;;
    --plain) PLAIN=1 ;;
    --section)
      [ $# -ge 2 ] || {
        printf 'wm-status: --section requires an argument\n' >&2
        exit 2
      }
      shift
      SECTION="$1"
      ;;
    -h | --help)
      printf 'usage: %s [--watch|--once] [--plain] [--section net|disk|cpu|mem|vol|time]\n' \
        "$(basename "$0")"
      exit 0
      ;;
    net | disk | cpu | mem | vol | time) SECTION="$1" ;;
    *)
      printf 'wm-status: unknown option %s\n' "$1" >&2
      exit 2
      ;;
  esac
  shift
done

case "$SECTION" in
  "" | net | disk | cpu | mem | vol | time) ;;
  *)
    printf 'wm-status: unknown section %s\n' "$SECTION" >&2
    exit 2
    ;;
esac

if [ "$MODE" = "watch" ]; then
  while true; do
    collect
    build_segments
    render
    sleep "$POLL_INTERVAL"
  done
else
  collect
  build_segments
  render
fi
