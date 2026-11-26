#!/usr/bin/env bash
exec >>/tmp/battery_debug.log 2>&1
echo "Battery monitor started at $(date)"

THRESHOLD=4
# Calibration: the hardware cuts off ~2% true charge before the gauge
# reaches 0 (popup once read 1.00% with a -1 offset). The offset is passed
# to the applet so it displays 0.00% as it dies, and the trigger fires
# OFFSET points earlier (raw capacity <= THRESHOLD + OFFSET) so the popup
# appears showing exactly THRESHOLD. One knob controls both.
OFFSET=2
BATTERY_PATH="/sys/class/power_supply/BAT0/capacity"
STATUS_PATH="/sys/class/power_supply/BAT0/status"
# Built by nix from nixos/battery-popup (home.packages), so it never loses
# its libraries to garbage collection. Make sure the per-user profile is on
# PATH even when awesome was started with a minimal environment.
export PATH="/etc/profiles/per-user/$USER/bin:$HOME/.nix-profile/bin:$PATH"
POPUP_EXEC="battery-popup"
INTERVAL=61 # seconds between checks
STATE_FILE="/tmp/battery_warning_shown"

while true; do
    if [[ ! -f "$BATTERY_PATH" || ! -f "$STATUS_PATH" ]]; then
        echo "Battery path not found. Skipping check."
        sleep "$INTERVAL"
        continue
    fi

    BATTERY=$(cat "$BATTERY_PATH")
    STATUS=$(cat "$STATUS_PATH")

    echo "Battery: $BATTERY% (shows $((BATTERY - OFFSET))%), Status: $STATUS"

    if [[ $((BATTERY - OFFSET)) -le "$THRESHOLD" && "$STATUS" != "Charging" ]]; then
        if [[ ! -f "$STATE_FILE" ]]; then
            echo "Triggering popup..."
            "$POPUP_EXEC" "$OFFSET" &
            touch "$STATE_FILE"
        else
            echo "Popup already shown. Skipping."
        fi
    else
        if [[ -f "$STATE_FILE" ]]; then
            echo "Battery ok or charging. Resetting state."
            rm "$STATE_FILE"
        else
            echo "Battery ok. No popup needed."
        fi
    fi

    sleep "$INTERVAL"
done
