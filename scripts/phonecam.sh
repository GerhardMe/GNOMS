#!/usr/bin/env bash
# phonecam.sh — iPhone camera in a floating mpv window
# Usage: phonecam [phone-ip] [-r DEG] | stop | status
#
# The DroidCam app serves the camera at http://<phone-ip>:4747/video. The
# laptop connects out, so no firewall change. The phone IP is remembered, so
# it is only needed once (or when it changes). Until the app is open, mpv
# keeps retrying. The image is mirrored (hflip) and rotated by -r/--rotate DEG
# (0/90/180/270, clockwise); the rotation is remembered like the IP.
# Running it again reopens the window (e.g. with a new IP or rotation).

set -uo pipefail

RUN_DIR="${XDG_RUNTIME_DIR:-/tmp}/gnoms-phonecam"
CAM_PID="$RUN_DIR/phonecam.pid"
CAM_LOG="$RUN_DIR/phonecam.log"
CONF_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/phonecam"
CAM_IP_FILE="$CONF_DIR/ip"
CAM_ROT_FILE="$CONF_DIR/rotate"
CAM_PORT=4747

RED=$'\033[91m'; YELLOW=$'\033[93m'; RESET=$'\033[0m'
err()  { printf "${RED}ERROR:${RESET} %s\n" "$*" >&2; }
warn() { printf "${YELLOW}⚠ %s${RESET}\n" "$*" >&2; }

cam_running() {
  [[ -f "$CAM_PID" ]] && kill -0 "$(<"$CAM_PID")" 2>/dev/null
}

# Remember a phone address given on the command line ("ip" or "ip:port")
save_cam_ip() {
  [[ -n "${1:-}" ]] || return 0
  mkdir -p "$CONF_DIR"
  printf '%s\n' "$1" >"$CAM_IP_FILE"
}

# Parse "[phone-ip] [-r|--rotate DEG]" into CAM_ARG_IP / CAM_ARG_ROT
parse_cam_args() {
  CAM_ARG_IP="" CAM_ARG_ROT=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
    -r | --rotate)
      [[ "${2:-}" =~ ^(0|90|180|270)$ ]] || { err "rotation must be 0, 90, 180 or 270"; return 1; }
      CAM_ARG_ROT="$2"
      shift 2
      ;;
    --rotate=*)
      [[ "${1#*=}" =~ ^(0|90|180|270)$ ]] || { err "rotation must be 0, 90, 180 or 270"; return 1; }
      CAM_ARG_ROT="${1#*=}"
      shift
      ;;
    -*) err "unknown option: $1"; return 1 ;;
    *) CAM_ARG_IP="$1"; shift ;;
    esac
  done
}

# Remember a rotation given on the command line
save_cam_rot() {
  [[ -n "${1:-}" ]] || return 0
  mkdir -p "$CONF_DIR"
  printf '%s\n' "$1" >"$CAM_ROT_FILE"
}

start_cam() {
  local addr
  [[ -f "$CAM_IP_FILE" ]] && addr=$(tr -d ' \t\r\n' <"$CAM_IP_FILE")
  [[ -n "${addr:-}" ]] || { err "no phone IP: run 'phonecam <phone-ip>'"; return 1; }
  [[ "$addr" == *:* ]] || addr="$addr:$CAM_PORT"
  local rot=0
  [[ -f "$CAM_ROT_FILE" ]] && rot=$(tr -d ' \t\r\n' <"$CAM_ROT_FILE")
  stop_cam
  command -v mpv >/dev/null || { err "mpv not installed"; return 1; }
  [[ -n "${DISPLAY:-}" ]] || { err "DISPLAY not set; the camera window needs X"; return 1; }
  mkdir -p "$RUN_DIR"
  # setsid makes the loop a process group leader, so stop_cam can kill it
  # together with its mpv. mpv exits 2 when the stream cannot be opened
  # (app not open yet): retry. Any other exit (q, window closed) ends it.
  setsid bash -c '
    while :; do
      mpv --profile=low-latency --untimed --no-cache --no-audio \
          --vf=hflip --video-rotate="$2" \
          --title=phonecam --x11-name=phonecam "$1"
      [[ $? -eq 2 ]] || break
      sleep 2
    done' _ "http://$addr/video" "$rot" >"$CAM_LOG" 2>&1 </dev/null &
  echo $! >"$CAM_PID"
  disown
  echo "Camera window: http://$addr/video, rotated ${rot}° (open DroidCam on the iPhone)"
}

stop_cam() {
  cam_running && kill -- -"$(<"$CAM_PID")" 2>/dev/null
  rm -f "$CAM_PID"
}

case "${1:-}" in
stop)
  stop_cam
  ;;
status)
  cam_running && echo ON || echo OFF
  ;;
-h | --help | help)
  echo "Usage: phonecam [phone-ip] [-r 0|90|180|270] | stop | status"
  ;;
*)
  parse_cam_args "$@" || exit 1
  save_cam_ip "$CAM_ARG_IP"
  save_cam_rot "$CAM_ARG_ROT"
  start_cam
  ;;
esac
