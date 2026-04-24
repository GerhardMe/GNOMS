#!/usr/bin/env bash
# mcflash - Flash firmware to microcontrollers
# Usage: mcflash [--via-jlink] <firmware.{bin|uf2|hex|py}> [extra-args]
#
# Options:
#   --via-jlink   Flash THROUGH the J-Link to an external target board
#                 (instead of TO the dev kit's onboard chip)

set -Eeuo pipefail

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=lib/microcontroller.sh
. "$SCRIPT_DIR/lib/microcontroller.sh"

MPY_AUTORUN_AFTER_RECONNECT="${MPY_AUTORUN_AFTER_RECONNECT:-1}"

# ===================== MicroPython Helpers =====================

mpy_push() {
  local port="$1" file="$2"
  have mpremote || die "mpremote not installed"

  # Free FS before copy
  mpremote connect "port:${port}" rawrepl "exec(\"import machine; machine.soft_reset()\")" >/dev/null 2>&1 || true

  local remote=":/main.py"
  if mpremote --help | grep -qE ' cp '; then
    mpremote connect "port:${port}" cp "$file" "$remote" ||
      { sleep 1; mpremote connect "port:${port}" cp "$file" "$remote"; }
  else
    mpremote connect "port:${port}" fs cp "$file" "$remote" ||
      { sleep 1; mpremote connect "port:${port}" fs cp "$file" "$remote"; }
  fi

  mpremote connect "port:${port}" exec "import os; os.stat('/main.py')" >/dev/null 2>&1 ||
    die "mpremote copy verification failed (missing /main.py)"

  log "[MPY] soft-reset to start /main.py"
  mpremote connect "port:${port}" soft-reset >/dev/null 2>&1 || true
}

mpy_force_start() {
  local port="$1"
  [[ "${MPY_AUTORUN_AFTER_RECONNECT}" == "1" ]] || return 0
  [[ -e "$port" ]] || { log "[MPY] port gone: $port"; return 0; }

  # Try mpremote first
  if have mpremote; then
    log "[MPY] reset via mpremote"
    if mpremote connect "port:${port}" reset >/dev/null 2>&1; then return 0; fi
    if mpremote connect "port:${port}" soft-reset >/dev/null 2>&1; then return 0; fi
    log "[MPY] mpremote reset failed; trying raw TTY"
  fi

  # Raw TTY fallback
  if have python3; then
    python3 - "$port" <<'PY' 2>/dev/null || true
import os, sys, time, termios
port = sys.argv[1]
fd = os.open(port, os.O_RDWR | os.O_NOCTTY | os.O_NONBLOCK)
attrs = termios.tcgetattr(fd)
attrs[0] = 0; attrs[1] = 0
attrs[2] = termios.B115200 | termios.CS8 | termios.CREAD | termios.CLOCAL
attrs[3] = 0
termios.tcsetattr(fd, termios.TCSANOW, attrs)
def w(b): os.write(fd, b)
try:
    w(b'\x03\x03')
    time.sleep(0.15)
    w(b"import machine\r\nmachine.reset()\r\n")
    time.sleep(0.3)
    w(b'\x04')
finally:
    os.close(fd)
PY
    log "[MPY] raw reset sequence sent on $port"
    return 0
  fi

  # Minimal fallback
  if have stty; then
    log "[MPY] minimal reset via stty/printf"
    stty -F "$port" raw -echo 115200 || true
    printf '\003\003' >"$port" 2>/dev/null || true
    printf 'import machine\r\nmachine.reset()\r\n' >"$port" 2>/dev/null || true
    printf '\004' >"$port" 2>/dev/null || true
  fi
}

# ===================== Auto-Connect Restart =====================

restart_repl() {
  local newport="${1:-}"
  local script=""

  if command -v microcontroller-connect.sh >/dev/null 2>&1; then
    script="$(command -v microcontroller-connect.sh)"
  elif [[ -x "$SCRIPT_DIR/microcontroller-connect.sh" ]]; then
    script="$SCRIPT_DIR/microcontroller-connect.sh"
  else
    die "microcontroller-connect.sh not found"
  fi

  log "[post] launching $script ${newport:+--port $newport}"
  if [[ -n "$newport" ]]; then
    nohup "$script" --port "$newport" >/dev/null 2>&1 &
  else
    nohup "$script" >/dev/null 2>&1 &
  fi
  disown || die "failed to start auto-connect script"
}

# ===================== Argument Parsing =====================

VIA_JLINK=0
FILE=""

while [[ $# -gt 0 ]]; do
  case "$1" in
    --via-jlink)
      VIA_JLINK=1
      shift
      ;;
    -h|--help)
      echo "Usage: mcflash [--via-jlink] <firmware.{bin|uf2|hex|py}> [extra-args]"
      echo ""
      echo "Options:"
      echo "  --via-jlink   Flash THROUGH J-Link to external target"
      echo "                (default: flash TO the dev kit's onboard chip)"
      exit 0
      ;;
    -*)
      die "unknown option: $1 (use --help for usage)"
      ;;
    *)
      FILE="$1"
      shift
      break
      ;;
  esac
done

[[ -n "$FILE" ]] || die "usage: mcflash [--via-jlink] <firmware.{bin|uf2|hex|py}> [extra-args]"
[[ -f "$FILE" ]] || die "file not found: $FILE"

# ===================== Load State =====================

PORT="${PORT:-}"
TYPE="${TYPE:-}"
JLINK_PORT="${JLINK_PORT:-}"

if [[ -z "${PORT}" || -z "${TYPE}" ]]; then
  [[ -f "$STATE_FILE" ]] || die "no device info; run microcontroller-connect.sh first"
  # shellcheck disable=SC1090
  source "$STATE_FILE"
fi

[[ -n "${PORT:-}" ]] || die "no PORT found (env or $STATE_FILE)"
[[ -n "${TYPE:-}" ]] || die "no TYPE found (env or $STATE_FILE)"
[[ -e "$PORT" ]] || die "port not present: $PORT"
is_ignored_port "$PORT" && die "refusing to flash ignored device: $PORT"
port_rw_ok "$PORT" || die "no permission on $PORT (need rw)"

EXT="${FILE##*.}"
EXT="${EXT,,}"

# Free the line before flashing
close_users_of_port "$PORT"
wait_until_free "$PORT" || die "port is still busy: $PORT"

# ===================== Flash by Extension =====================

NEWPORT=""

case "$EXT" in

  # -------------------- ESP32/ESP8266 --------------------
  bin)
    tool="esptool.py"
    have esptool && tool="esptool"
    have "$tool" || die "esptool not installed"

    OFFSET="${ESP_OFFSET:-0x10000}"
    log "[ESP] tool=$tool port=$PORT offset=$OFFSET file=$FILE"
    "$tool" --chip auto -p "$PORT" --before default_reset --after hard_reset \
      write_flash "$OFFSET" "$FILE" "$@"

    NEWPORT="$(wait_replug "$PORT" "${ESP_REPLUG_TIMEOUT:-20}" "${ESP_BYID_REGEX:-ESP|Silicon_Labs|CP210|CH340}" || true)"
    ;;

  # -------------------- Raspberry Pi Pico --------------------
  uf2)
    have picotool || die "picotool not installed"

    log "[PICO] rebooting to BOOTSEL"
    picotool reboot -f || true

    log "[PICO] loading UF2: $FILE"
    picotool load -v -x "$FILE"

    log "[PICO] rebooting app"
    picotool reboot || true

    NEWPORT="$(wait_replug "$PORT" "${PICO_REPLUG_TIMEOUT:-20}" "${PICO_BYID_REGEX:-Pico|RP2040}" || true)"
    ;;

  # -------------------- HEX files (Nordic or Arduino) --------------------
  hex)
    if [[ "$TYPE" == "NORDIC_DK" || "$TYPE" == "JLINK" || "$TYPE" == "NORDIC" ]]; then
      # Nordic path: use nrfutil (modern replacement for nrfjprog)
      have nrfutil || die "nrfutil not installed"

      # Ensure device extension is installed (required for flashing)
      if ! nrfutil device --help &>/dev/null; then
        log "[NRF] installing nrfutil device extension..."
        nrfutil install device || die "failed to install nrfutil device extension"
      fi

      if [[ "$VIA_JLINK" -eq 1 ]]; then
        log "[NRF] flashing EXTERNAL target via J-Link"
      else
        log "[NRF] flashing DK onboard chip"
      fi

      # nrfutil device program syntax:
      # --firmware: the hex file
      # --options: verify=VERIFY_READ, chip_erase_mode=ERASE_RANGES (sector erase)
      nrfutil device program \
        --firmware "$FILE" \
        --options verify=VERIFY_READ,chip_erase_mode=ERASE_RANGES \
        "$@"

      # Reset the device to start the new firmware
      nrfutil device reset || true

      # Wait for device to reset and re-enumerate
      sleep 1

      # Find UART port for serial output
      if [[ "$TYPE" == "NORDIC_DK" ]]; then
        NEWPORT="$(find_nordic_uart "${JLINK_PORT:-$PORT}" || true)"
      fi
    else
      # Arduino AVR path: use avrdude
      have avrdude || die "avrdude not installed"

      AVR_MCU="${AVR_MCU:-atmega328p}"
      AVR_BAUD="${AVR_BAUD:-115200}"
      AVR_PROG="${AVR_PROG:-arduino}"

      log "[AVR] mcu=$AVR_MCU prog=$AVR_PROG baud=$AVR_BAUD port=$PORT"
      avrdude -p "$AVR_MCU" -c "$AVR_PROG" -P "$PORT" -b "$AVR_BAUD" -D -U "flash:w:$FILE:i"

      NEWPORT="$(wait_replug "$PORT" "${AVR_REPLUG_TIMEOUT:-12}" "${AVR_BYID_REGEX:-Arduino|FTDI|CH340|CP210}" || true)"
    fi
    ;;

  # -------------------- MicroPython --------------------
  py)
    log "[MPY] copying to /main.py (autostart)"
    mpy_push "$PORT" "$FILE"
    # MPY keeps same port, no replug wait needed
    ;;

  *)
    die "unknown file type: .$EXT (supported: .bin .uf2 .hex .py)"
    ;;
esac

# ===================== Post-Flash: Restart REPL =====================

POSTPORT="$PORT"
if [[ -n "${NEWPORT:-}" && -e "$NEWPORT" ]]; then
  POSTPORT="$NEWPORT"
fi

# Kick MicroPython so /main.py runs (safe no-op on non-MPY)
mpy_force_start "$POSTPORT"

# Launch terminal on the right port
log "[post] starting connector on $POSTPORT"
restart_repl "$POSTPORT"

echo "[ok] done."
