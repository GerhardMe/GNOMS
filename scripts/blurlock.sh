#!/usr/bin/env bash
set -euo pipefail

# Exclusive lock — FD 9 is inherited by `exec i3lock`, which holds the flock
# until the user unlocks. This replaces pgrep and prevents concurrent runs.
exec 9>/tmp/blurlock.lock
flock -n 9 || exit 0

# Don't lock right after boot
UPTIME=$(awk '{print int($1)}' /proc/uptime)
if ((UPTIME < 50)); then
  exit 0
fi

IMG=/tmp/blurlock_screen.png
OVER="$HOME/.cache/blurlock_overlay.png"
BLUR="0x1"

LOCK_CHAR=$''

# Remove screenshot on any non-exec exit (error paths only; exec bypass is intentional)
cleanup() { rm -f "$IMG"; }
trap cleanup EXIT

# Build overlay once; cache it across invocations
if [[ ! -f "$OVER" ]]; then
  FONTFILE="$(fc-list -f '%{file}\n' | grep -i -E 'SymbolsNerdFontMono|NerdFont.*Mono' | head -n1 || true)"
  if [[ -z "$FONTFILE" ]]; then
    dunstify -u critical "blurlock" "No Nerd Font found — install a Nerd Font."
    exit 1
  fi
  mkdir -p "$(dirname "$OVER")"
  magick -size 600x600 xc:none \
    -gravity center \
    -fill "#BABABA" -stroke "#292929" -strokewidth 2 \
    -font "$FONTFILE" -pointsize 160 \
    -annotate -1-6 "$LOCK_CHAR" \
    "$OVER"
fi

dunstify -u normal -t 700 -h string:fgcolor:#00ffff "🔒 Locking Computer..."

# Single-pass: screenshot → blur → composite overlay → write file
maim -u | magick - \
  -scale 10% -blur "$BLUR" -resize 1000% \
  \( "$OVER" \) -gravity center -compose over -composite \
  -define png:compression-level=1 \
  "$IMG"

exec i3lock -i "$IMG"
