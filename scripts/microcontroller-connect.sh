#!/usr/bin/env bash
set -Eeuo pipefail

# Source shared library
SCRIPT_DIR="$(cd "$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")" && pwd)"
# shellcheck source=lib/microcontroller.sh
. "$SCRIPT_DIR/lib/microcontroller.sh"

# ===================== MicroPython Detection =====================

is_micropython() {
	local port="$1"
	have mpremote || return 1

	local out
	out=$(mpremote --quiet connect "port:${port}" exec "import sys; print(sys.implementation.name)" 2>/dev/null ||
		mpremote --quiet exec "import sys; print(sys.implementation.name)" 2>/dev/null || true)
	echo "$out" | grep -qi "micropython"
}

# ===================== Device Classification =====================

classify() {
	local port="$1" vid="$2"

	# MicroPython check first (probes the device)
	if is_micropython "$port"; then
		echo "MICROPY"
		return 0
	fi

	case "$vid" in
	1366) # Segger J-Link
		local product
		product="$(get_product "$port")"
		if [[ "$product" == *"J-Link"* || "$product" == *"J_Link"* ]]; then
			if is_nordic_dk; then
				echo "NORDIC_DK"
			else
				echo "JLINK"
			fi
		else
			echo "GENERIC"
		fi
		;;
	1915) # Nordic Semiconductor (older devices)
		if is_nordic_dk; then
			echo "NORDIC_DK"
		else
			echo "NORDIC"
		fi
		;;
	303a) echo "ESP" ;;
	2e8a) echo "PICO" ;;
	2341 | 2a03) echo "ARDUINO" ;;
	*) echo "GENERIC" ;;
	esac
}

# ===================== Terminal Opening =====================

open_terminal() {
	local port="$1" baud="$2"
	local cmd="picocom -b $baud --imap lfcrlf --omap crcrlf --nolock '$port'"

	if have wezterm; then
		wezterm start -- bash -lc "$cmd"
	elif have xterm; then
		xterm -T "Serial ($port)" -e bash -lc "$cmd" &
	elif have gnome-terminal; then
		gnome-terminal -- bash -lc "$cmd" &
	elif have konsole; then
		konsole -e bash -lc "$cmd" &
	else
		eval "$cmd"
	fi
}

open_rtt() {
	# Open an RTT viewer for Nordic bare-metal firmware via probe-rs.
	# probe-rs reads RTT output directly from RAM over the J-Link debug
	# connection — no UART or serial port involved.
	# probe-rs attach requires the ELF file to locate the RTT control block.
	# The ELF path is saved by mcflash to /tmp/mcdev_elf.
	local chip="${NRF_CHIP:-nRF54L15}"

	local elf=""
	if [[ -f /tmp/mcdev_elf ]]; then
		elf="$(cat /tmp/mcdev_elf)"
	fi

	if [[ -z "$elf" || ! -f "$elf" ]]; then
		log "no ELF found at /tmp/mcdev_elf — flash first to enable RTT"
		notify "Nordic DK" "Flash firmware first to enable RTT viewer"
		return 0
	fi

	local cmd="probe-rs attach --chip $chip '$elf'; echo '--- RTT session ended, press enter to close ---'; read"

	if have wezterm; then
		wezterm start --always-new-process -- bash -lc "$cmd" &
	elif have xterm; then
		xterm -T "RTT ($chip)" -e bash -lc "$cmd" &
	elif have gnome-terminal; then
		gnome-terminal --title "RTT ($chip)" -- bash -lc "$cmd" &
	elif have konsole; then
		konsole --title "RTT ($chip)" -e bash -lc "$cmd" &
	else
		eval "$cmd"
	fi
}

# ===================== Main =====================

main() {
	# Brief delay for udev to settle
	sleep 0.4

	# Find first usable serial port
	local PORT=""
	for p in $(pick_serial); do
		[[ -e "$p" ]] || continue
		if is_ignored_port "$p"; then
			continue
		fi
		PORT="$p"
		break
	done

	if [[ -z "$PORT" ]]; then
		log "no usable serial device"
		rm -f "$STATE_FILE"
		exit 0
	fi

	# Check permissions
	if [[ ! -r "$PORT" || ! -w "$PORT" ]]; then
		local grp
		grp=$(stat -c %G "$PORT" 2>/dev/null || echo '?')
		log "no permission on $PORT"
		notify "No permission" "$PORT (group $grp)"
		exit 1
	fi

	# Classify device
	local VID TYPE
	VID="$(get_vid "$PORT" || true)"
	TYPE="$(classify "$PORT" "$VID")"

	log "selected: port=$PORT vid=${VID:-??} type=$TYPE byid=$(byid_name_for "$PORT")"

	# For Nordic DK, we want the target UART, not the J-Link CDC port
	local UART_PORT="$PORT"
	if [[ "$TYPE" == "NORDIC_DK" ]]; then
		local target_uart
		target_uart="$(find_nordic_uart "$PORT")"
		if [[ -n "$target_uart" && -e "$target_uart" ]]; then
			UART_PORT="$target_uart"
			log "nordic: using UART port $UART_PORT (not J-Link CDC $PORT)"
		fi
	fi

	# Save state for mcflash
	{
		echo "PORT=$UART_PORT"
		echo "TYPE=$TYPE"
		[[ "$TYPE" == "NORDIC_DK" || "$TYPE" == "JLINK" ]] && echo "JLINK_PORT=$PORT"
	} >"$STATE_FILE"

	# Notify user
	case "$TYPE" in
	MICROPY) notify "MicroPython" "Use: mcflash your_script.py" ;;
	ESP) notify "ESP" "Use: mcflash firmware.bin" ;;
	PICO) notify "Pico" "Use: mcflash firmware.uf2" ;;
	ARDUINO) notify "Arduino" "Use: mcflash sketch.hex" ;;
	NORDIC_DK) notify "Nordic DK" "mcflash fw.hex | --via-jlink for external" ;;
	JLINK) notify "J-Link" "Connect target, then: mcflash firmware.hex" ;;
	NORDIC) notify "Nordic" "Use: mcflash firmware.hex" ;;
	*) notify "Serial Device" "$PORT" ;;
	esac

	# Open terminal — method depends on device type
	case "$TYPE" in
	NORDIC_DK | NORDIC)
		# Nordic bare-metal uses RTT for output, not UART.
		# RTT only works after firmware has been flashed — skip on bare plug-in.
		# mcflash opens the RTT window directly after a successful flash.
		log "nordic: RTT viewer launched by mcflash after flashing"
		;;
	JLINK)
		# Standalone J-Link with no known target — nothing to open
		;;
	*)
		open_terminal "$UART_PORT" "$DEFAULT_BAUD"
		;;
	esac
}

main "$@"
