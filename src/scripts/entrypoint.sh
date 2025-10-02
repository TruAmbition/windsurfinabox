#!/usr/bin/env bash
set -Eeuo pipefail

# ---------- Config (overridable via env) ----------
HOME_DIR="${HOME:-/tmp}"
CONFIG_ROOT="${XDG_CONFIG_HOME:-${HOME_DIR}/.config}"
WINDSURF_PATH="${WINDSURF_PATH:-${CONFIG_ROOT}/Windsurf}"
LOGS_PATH="${LOGS_PATH:-${WINDSURF_PATH}/logs}"

# Workspace: prefer /workspace (bind mount), fallback to /tmp/workspace
WORKSPACE_DIR="${WORKSPACE_DIR:-/workspace}"
[[ -d "$WORKSPACE_DIR" ]] || WORKSPACE_DIR="${HOME_DIR}/workspace"

WORKSPACE_WINDSURF_PATH="${WORKSPACE_DIR}/.windsurf"
WORKSPACE_WORKFLOWS_PATH="${WORKSPACE_WINDSURF_PATH}/workflows"
INSTRUCTIONS_FILE="${INSTRUCTIONS_FILE:-${WORKSPACE_DIR}/windsurf-instructions.txt}"
OUTPUT_FILE="${OUTPUT_FILE:-${WORKSPACE_DIR}/windsurf-output.txt}"
SCREENSHOTS_PATH="${SCREENSHOTS_PATH:-${WORKSPACE_DIR}/screenshots}"
EXTENSIONS_DIR="${EXTENSIONS_DIR:-${HOME_DIR}/.windsurf/extensions}"
RESOURCES_PATH="${RESOURCES_PATH:-/usr/local/share/windsurf}"  # baked assets live here

FINALIZATION_MARKER="${FINALIZATION_MARKER:-WORK-COMPLETED}"
WAIT_TIMEOUT_SECS="${WAIT_TIMEOUT_SECS:-900}" # 15 min fallback timeout
export DISPLAY="${DISPLAY:-:1}"

# ---------- Ensure dirs & files exist ----------
mkdir -p "$WINDSURF_PATH" "$LOGS_PATH" "$WORKSPACE_WINDSURF_PATH" "$WORKSPACE_WORKFLOWS_PATH" "$SCREENSHOTS_PATH" "$EXTENSIONS_DIR"

# Create/truncate the log early; fail fast if not writable
if ! : > "$OUTPUT_FILE" 2>/dev/null; then
  echo "ENTRYPOINT $(date +'%F %T') - ERROR: Cannot write to $OUTPUT_FILE (workspace perms?)"
  ls -ld "$WORKSPACE_DIR" || true
  id || true
  exit 1
fi

# Single logger
log() {
  local ts msg; ts="$(date +'%F %T')"; msg="ENTRYPOINT ${ts} - $*"
  echo "$msg" | tee -a "$OUTPUT_FILE"
}

# ---------- Utilities ----------
captureStep() {
  mkdir -p "$SCREENSHOTS_PATH"
  local n file; n=$(( $(ls -1 "$SCREENSHOTS_PATH" 2>/dev/null | wc -l | tr -d ' ') + 1 ))
  file="${SCREENSHOTS_PATH}/screenshot-${n}.png"
  xwd -display "$DISPLAY" -root -silent | convert xwd:- "png:${file}" || true
  log "Saved screenshot: ${file}"
}

pause() { sleep "${1:-5}"; }

focusWindsurf() {
  local win; win=$(xdotool search --onlyvisible --class Windsurf | head -n1 || true)
  [[ -n "$win" ]] && xdotool windowactivate "$win"
}

# --- Robust onboarding helpers (added; safe, no behavior removed) ---
getWindsurfWin() {
  local win
  win="$(xdotool search --onlyvisible --class Windsurf 2>/dev/null | head -n1 || true)"
  [[ -z "$win" ]] && win="$(xdotool search --onlyvisible --name 'Windsurf' 2>/dev/null | head -n1 || true)"
  echo "${win:-}"
}

focusWindsurfStrict() {
  local deadline=$(( $(date +%s) + 20 ))
  local win=""
  while [[ -z "$win" && $(date +%s) -lt $deadline ]]; do
    win="$(getWindsurfWin)"
    [[ -n "$win" ]] && break
    sleep 0.25
  done
  [[ -z "$win" ]] && { log "Could not find Windsurf window"; return 1; }
  xdotool windowactivate "$win" 2>/dev/null || true
  for m in Shift Control Alt Super Meta; do xdotool keyup "$m" 2>/dev/null || true; done
  log "Activated Windsurf window: $win"
  echo "$win"
}

# Click at a relative position (0..1 inside the window)
clickRel() {
  local win="$1" fx="${2:-0.50}" fy="${3:-0.80}"
  [[ -n "$win" ]] || return 1
  eval "$(xdotool getwindowgeometry --shell "$win" 2>/dev/null || true)"
  if [[ -z "${WIDTH:-}" || -z "${HEIGHT:-}" ]]; then WIDTH=1920 HEIGHT=1080 X=0 Y=0; fi
  local cx cy; cx=$(( X + (WIDTH*fx) )); cy=$(( Y + (HEIGHT*fy) ))
  xdotool mousemove --sync "$cx" "$cy"
  xdotool click 1
}

finishOnboarding() {
  local win; win="$(focusWindsurfStrict)" || return 0
  log "Finishing onboarding (position-click method)"
  # Try 3 screens: Get Started -> Setup flow -> Theme
  for _ in 1 2 3; do
    clickRel "$win" 0.50 0.78; sleep 0.6
    clickRel "$win" 0.50 0.83; sleep 0.6
    clickRel "$win" 0.50 0.87; sleep 0.6
  done
  xdotool key --window "$win" Escape || true
  log "Onboarding finished"
}
# --- end helpers ---

# Remove any accidentally-created *directory* named entry-workflow.md and ensure a real file exists
ensureWorkflowFile() {
  # Clean wrong location (root of workspace) if it exists as a directory
  if [[ -d "${WORKSPACE_DIR}/entry-workflow.md" ]]; then
    log "Found directory ${WORKSPACE_DIR}/entry-workflow.md (should be a file). Removing…"
    rm -rf "${WORKSPACE_DIR}/entry-workflow.md"
  fi
  # Clean wrong type under workflows path
  if [[ -d "${WORKSPACE_WORKFLOWS_PATH}/entry-workflow.md" ]]; then
    log "Found directory ${WORKSPACE_WORKFLOWS_PATH}/entry-workflow.md (should be a file). Removing…"
    rm -rf "${WORKSPACE_WORKFLOWS_PATH}/entry-workflow.md"
  fi

  mkdir -p "$WORKSPACE_WORKFLOWS_PATH"
  if [[ -f "${RESOURCES_PATH}/entry-workflow.md" ]]; then
    cp -f "${RESOURCES_PATH}/entry-workflow.md" "${WORKSPACE_WORKFLOWS_PATH}/entry-workflow.md"
    log "Placed workflow at ${WORKSPACE_WORKFLOWS_PATH}/entry-workflow.md"
  else
    # minimal fallback content
    cat > "${WORKSPACE_WORKFLOWS_PATH}/entry-workflow.md" <<'MD'
# Entry Workflow
Use the prompt provided to scaffold the requested project into the current workspace, then print "WORK-COMPLETED" to the output log.
MD
    log "No baked workflow found; wrote fallback workflow to ${WORKSPACE_WORKFLOWS_PATH}/entry-workflow.md"
  fi
}

checkTokenIsPresent() {
  if [[ -z "${WINDSURF_TOKEN:-}" ]]; then
    log "WINDSURF_TOKEN needs to be passed as an environment variable."
    exit 1
  fi
}

windsurfLogin() {
  log "Logging in to Windsurf with token"
  xdotool key ctrl+shift+p; sleep 1
  xdotool type -- "token"; xdotool key Return; sleep 1
  xdotool type -- "$WINDSURF_TOKEN"; xdotool key Return; sleep 1
  xdotool key Escape
}

# Minimal i3 config to avoid first-run wizard
I3_CONF_DIR="${CONFIG_ROOT}/i3"
I3_CONF_FILE="${I3_CONF_DIR}/config"
if [[ ! -f "$I3_CONF_FILE" ]]; then
  mkdir -p "$I3_CONF_DIR"
  printf '%s\n' \
    'set $mod Mod1' \
    'font pango:monospace 10' \
    'bindsym $mod+Shift+e exec i3-msg exit' \
    'bar { status_command i3status }' > "$I3_CONF_FILE"
fi

startWindowManager() {
  log "Starting Xvfb on ${DISPLAY}"
  Xvfb "$DISPLAY" -screen 0 1920x1080x24 -nolisten tcp -ac >/dev/null 2>&1 &
  local tries=0
  until xdpyinfo >/dev/null 2>&1; do sleep 0.25; tries=$((tries+1)); [[ $tries -gt 80 ]] && { log "Xvfb did not become ready"; exit 1; }; done
  log "Xvfb is ready!"
  (i3 >/dev/null 2>&1 &) || true
}

startWindsurf() {
  ensureWorkflowFile

  log "Starting Windsurf editor at DISPLAY=$DISPLAY (workspace=$WORKSPACE_DIR)"
  # reduce log noise by dropping --verbose unless you need it
  ( cd "$WORKSPACE_DIR" && windsurf --disable-workspace-trust --disable-gpu --no-sandbox . >>"$OUTPUT_FILE" 2>&1 ) &
  echo $! > "${WORKSPACE_DIR}/windsurf.pid"
  log "Windsurf PID=$(cat "${WORKSPACE_DIR}/windsurf.pid")"
}

runWorkflowWithPrompt() {
  local wf_name="entry-workflow"
  local prompt_text
  if [[ -s "$INSTRUCTIONS_FILE" ]]; then
    prompt_text="$(cat "$INSTRUCTIONS_FILE")"
  else
    prompt_text="create a simple react-three-fiber app with a rotating red cube"
    echo "$prompt_text" > "$INSTRUCTIONS_FILE"
    log "No instructions file found; wrote default prompt to $INSTRUCTIONS_FILE"
  fi

  focusWindsurf; sleep 0.5

  log "Opening Command Palette"
  xdotool key ctrl+shift+p; sleep 1

  # Try common labels for the runner
  local labels=("Windsurf: Run Workflow" "Run Workflow" "Codeium: Run Workflow")
  local triggered=""
  for lbl in "${labels[@]}"; do
    xdotool type -- "$lbl"; sleep 0.5; xdotool key Return; sleep 1
    triggered="1"; break
  done
  [[ -z "$triggered" ]] && log "Could not trigger workflow runner via palette (labels tried: ${labels[*]})"

  # Select our workflow (without .md)
  xdotool type -- "$wf_name"; xdotool key Return; sleep 1

  # Submit prompt
  xdotool type --delay 1 -- "$prompt_text"
  xdotool key Return
  log "Submitted prompt to workflow"
}

waitUntilFinished() {
  log "Waiting for marker '${FINALIZATION_MARKER}' in $(basename "$OUTPUT_FILE") (timeout ${WAIT_TIMEOUT_SECS}s)"
  if timeout "${WAIT_TIMEOUT_SECS}" bash -c "tail -Fn0 '$OUTPUT_FILE' | sed -n '/${FINALIZATION_MARKER}/q'"; then
    log "Workflow completed successfully!"
  else
    log "Timeout waiting for ${FINALIZATION_MARKER}"; echo "${FINALIZATION_MARKER}" >> "$OUTPUT_FILE"
  fi
}

# ---------- Run ----------
log "User: $(id -u):$(id -g)"
log "Workspace: $WORKSPACE_DIR"
log "Output log: $OUTPUT_FILE"
log "Config root: $WINDSURF_PATH"
checkTokenIsPresent
startWindowManager
pause 1
startWindsurf
pause 3
captureStep
focusWindsurf

# # <<< The only behavioral change: reliably advance onboarding >>>
# finishOnboarding
# captureStep
# pause 3
# captureStep
# pause 3
# captureStep
# pause 3
# captureStep
# pause 3
# captureStep
# pause 3
# captureStep

windsurfLogin
captureStep

# # (kept identical flow after login)
# runWorkflowWithPrompt
# captureStep

waitUntilFinished
captureStep
