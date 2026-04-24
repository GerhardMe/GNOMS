#!/usr/bin/env bash
# Shared library for microcontroller scripts
# Source this file: . "$(dirname "$0")/lib/microcontroller.sh"

# ===================== Configuration =====================
IGNORE_PORTS=${IGNORE_PORTS:-"/dev/ttyACM0"}
IGNORE_VIDS=${IGNORE_VIDS:-"2cb7"}  # Fibocom modem (Nordic/Segger handled separately)
DEFAULT_BAUD=${DEFAULT_BAUD:-115200}
STATE_FILE="/tmp/mcdev"

# ===================== Utility Functions =====================

have() { command -v "$1" >/dev/null 2>&1; }

log() { printf '[%s] %s\n' "$(date +%H:%M:%S)" "$*"; }

die() {
  printf "mc: %s\n" "$*" >&2
  exit 1
}

notify() {
  if have dunstify; then
    dunstify "$1" "$2" || true
  else
    notify-send "$1" "$2" || true
  fi
}

# ===================== udev Helpers =====================

udev_prop() {
  udevadm info -q property -n "$1" 2>/dev/null | sed -n "s/^$2=//p" | head -n1
}

get_vid() {
  local v
  v=$(udev_prop "$1" ID_VENDOR_ID || true)
  printf "%s" "${v,,}"
}

get_pid() {
  local p
  p=$(udev_prop "$1" ID_MODEL_ID || true)
  printf "%s" "${p,,}"
}

get_product() {
  local p
  p=$(udev_prop "$1" ID_MODEL || true)
  printf "%s" "$p"
}

get_serial() {
  local s
  s=$(udev_prop "$1" ID_SERIAL_SHORT || true)
  printf "%s" "$s"
}

# ===================== Port Filtering =====================

is_ignored_port() {
  local p="$1"

  # Check explicit port ignore list
  for x in $IGNORE_PORTS; do
    [[ "$p" == "$x" ]] && {
      log "ignore(port): $p"
      return 0
    }
  done

  # Check VID ignore list
  local vid
  vid="$(get_vid "$p" || true)"
  for v in $IGNORE_VIDS; do
    [[ -n "$vid" && "${vid,,}" == "${v,,}" ]] && {
      log "ignore(vid=$vid): $p"
      return 0
    }
  done

  return 1
}

# ===================== Device Discovery =====================

byid_name_for() {
  [[ -d /dev/serial/by-id ]] || { echo ""; return; }

  local dev="$1" link
  for link in /dev/serial/by-id/*; do
    [[ -e "$link" ]] || continue
    [[ "$(readlink -f "$link")" == "$dev" ]] && {
      basename "$link"
      return
    }
  done
  echo ""
}

pick_serial() {
  # Prefer stable /dev/serial/by-id paths
  if [[ -d /dev/serial/by-id ]]; then
    for s in /dev/serial/by-id/*; do
      [[ -e "$s" ]] || continue
      readlink -f "$s"
    done
  fi
  # Fallback to direct device nodes
  ls -t /dev/ttyACM* /dev/ttyUSB* 2>/dev/null || true
}

# ===================== Port Access =====================

port_rw_ok() { [[ -r "$1" && -w "$1" ]]; }

close_users_of_port() {
  local port="$1" killed=0

  if have fuser; then
    fuser -k "$port" 2>/dev/null && killed=1 || true
  fi

  if have lsof; then
    local pids
    pids="$(lsof -t "$port" 2>/dev/null || true)"
    [[ -n "$pids" ]] && {
      kill $pids 2>/dev/null || true
      killed=1
    }
  fi

  [[ $killed -eq 1 ]] && sleep 0.6
}

wait_until_free() {
  local port="$1" tries="${2:-30}"

  for _ in $(seq 1 "$tries"); do
    if ! lsof "$port" &>/dev/null && ! fuser "$port" &>/dev/null; then
      return 0
    fi
    sleep 0.2
  done
  return 1
}

wait_replug() {
  # Wait for device to re-enumerate after reset
  # $1: old devnode, $2: timeout(s), $3: grep regex for by-id preference
  local old="$1" t_end=$((SECONDS + ${2:-20})) prefer="${3:-.}"

  # Wait for old device to disappear
  while [[ -e "$old" && SECONDS -lt $t_end ]]; do sleep 0.2; done

  # Wait for new device to appear
  while ((SECONDS < t_end)); do
    local byid
    byid="$(ls -1t /dev/serial/by-id/ 2>/dev/null | grep -E "$prefer" | head -n1 || true)"
    if [[ -n "$byid" && -e "/dev/serial/by-id/$byid" ]]; then
      readlink -f "/dev/serial/by-id/$byid"
      return 0
    fi

    local n
    n="$(ls -1t /dev/ttyACM* /dev/ttyUSB* 2>/dev/null | head -n1 || true)"
    [[ -n "$n" ]] && { echo "$n"; return 0; }

    sleep 0.2
  done
  return 1
}

# ===================== Nordic/Segger Helpers =====================

is_segger_device() {
  local vid="$1"
  [[ "$vid" == "1366" ]]
}

is_nordic_dk() {
  # Nordic DKs have multiple ACM ports (J-Link CDC + target UART)
  local acm_count
  acm_count=$(ls /dev/ttyACM* 2>/dev/null | wc -l)
  (( acm_count >= 2 ))
}

find_nordic_uart() {
  # Nordic DKs: ACM0 = J-Link CDC, ACM1+ = target UART
  # Find highest-numbered ACM port (usually the target UART)
  local exclude="${1:-}"
  local ports
  ports=$(ls -1 /dev/ttyACM* 2>/dev/null | sort -V)

  for p in $ports; do
    [[ "$p" != "$exclude" ]] && echo "$p"
  done | tail -n1
}

get_jlink_serial() {
  # Get J-Link serial number for nrfjprog --snr
  local port="$1"
  get_serial "$port"
}
