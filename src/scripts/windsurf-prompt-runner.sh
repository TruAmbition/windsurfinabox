#!/usr/bin/env bash
set -Eeuo pipefail

CONTAINER_NAME="windsurf"

# --- read prompt from arg / file / stdin ---
get_prompt() {
  if [[ $# -eq 0 ]]; then
    echo "Usage: $0 \"your prompt\" | @/path/to/file | -" >&2
    exit 1
  fi
  case "$1" in
    -)  cat ;;                         # from stdin
    @*) cat "${1#@}" ;;                # from file after '@'
    *)  printf "%s" "$1" ;;            # literal
  esac
}
PROMPT_TEXT="$(get_prompt "${1:-}"). When you are done with the changes, save and close all files in the editor window"

# --- cleanup on exit / Ctrl+C ---
cleanup() {
  echo "Stopping and removing container ${CONTAINER_NAME}..."
  docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true
}
trap cleanup INT TERM EXIT

# ensure config volume exists
docker volume create windsurf_config >/dev/null 2>&1 || true

# remove any previous container with same name
docker rm -f "${CONTAINER_NAME}" >/dev/null 2>&1 || true

# run container **detached** so we can exec into it next
docker run -d --name "${CONTAINER_NAME}" \
  --user "$(id -u):$(id -g)" \
  -e TRUPROMPT="${PROMPT_TEXT}" \
  -e WINDSURF_TOKEN="${WINDSURF_TOKEN:?WINDSURF_TOKEN not set}" \
  -e XDG_CONFIG_HOME=/config \
  -e HOME=/workspace \
  -e WORKSPACE_DIR=/workspace \
  -e PROJECT_NAME=tmy-r3f-cube \
  -e LIBGL_ALWAYS_SOFTWARE=1 \
  -e MESA_LOADER_DRIVER_OVERRIDE=llvmpipe \
  -e ELECTRON_DISABLE_GPU=1 \
  -v windsurf_config:/config \
  -v "$HOME/windsurf-workspace:/workspace" \
  -p 6080:6080 \
  -p 5901:5901 \
  -p 5173:5173 \
  -p 3000:3000 \
  --shm-size=2g \
  windsurf >/dev/null

# small wait to let Xvfb / app boot
sleep 2

# optional: create VNC dir as root (harmless if it already exists)
docker exec -u 0:0 "${CONTAINER_NAME}" bash -lc 'mkdir -p /root/.vnc' >/dev/null

# start x11vnc (passwordless). If your image doesn’t have it installed,
# install it in the Dockerfile or run: apt-get update && apt-get install -y x11vnc
docker exec -d "${CONTAINER_NAME}" bash -lc \
  'x11vnc -display :1 -nopw -forever -shared -rfbport 5901 >/var/log/x11vnc.log 2>&1 || true'

# start noVNC websocket (needs novnc + websockify installed in the image)
docker exec -d "${CONTAINER_NAME}" bash -lc \
  'websockify --web=/usr/share/novnc 6080 localhost:5901 >/var/log/novnc.log 2>&1 || true'

echo ""
echo "✅ Container is running: ${CONTAINER_NAME}"
echo "   • noVNC:   http://localhost:6080  (VNC-in-browser)"
echo "   • VNC:     localhost:5901         (native VNC client)"
echo "   • Project: $HOME/windsurf-workspace"
echo "   • Prompt:  ${PROMPT_TEXT}"
echo ""
echo "Press Ctrl+C to stop and remove the container."
# keep the script alive so traps fire and ports stay open
# tail the container logs (Ctrl+C to exit)
docker logs -f "${CONTAINER_NAME}"
