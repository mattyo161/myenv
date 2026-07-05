#!/bin/bash
# travel-mode — keep a MacBook awake (even lid-closed on battery) and its
# internet connection alive while working off an iPhone hotspot or hopping
# between networks. See README.md alongside this script for the full story.
#
#   travel-mode run       foreground; Ctrl-C stops and reverts everything
#   travel-mode start     background service (launchd LaunchAgent)
#   travel-mode stop      stop the service and restore normal sleep
#   travel-mode status    service / connectivity / sleep-override state
#   travel-mode logs      tail the service log
#
# Only `pmset -a disablesleep` needs root; everything else runs as you. The
# ansible extra (roles/extras/tasks/*/84-travel-mode.yml) installs a sudoers
# drop-in scoped to exactly that command so the service never prompts.
set -u

# ---- configuration -----------------------------------------------------------
# Defaults below; override any of them in ~/.config/travel-mode/config, which
# is a plain shell fragment (sourced if present). WiFi passwords are never
# stored here — reconnect relies on networks already saved in the Keychain.
TRAVEL_MODE_WIFI_DEV=en0
TRAVEL_MODE_NETWORKS=()
TRAVEL_MODE_INTERVAL=30

CONFIG_FILE="${HOME}/.config/travel-mode/config"
# shellcheck source=/dev/null
[ -f "$CONFIG_FILE" ] && . "$CONFIG_FILE"

LABEL="local.travel-mode"
PLIST="${HOME}/Library/LaunchAgents/${LABEL}.plist"
LOG_FILE="${HOME}/Library/Logs/travel-mode.log"
SCRIPT_PATH="$(cd "$(dirname "$0")" && pwd)/$(basename "$0")"

log() { echo "travel-mode: $*"; }

# ---- sleep override (the only root operation) ---------------------------------
# `pmset -a disablesleep 1` keeps the machine awake even with the lid closed on
# battery. It requires root; the sudoers drop-in makes `sudo -n` succeed without
# a password. Interactive contexts fall back to a normal sudo prompt.
sleep_override() { # $1 = 1|0, $2 = interactive|quiet
  if sudo -n /usr/bin/pmset -a disablesleep "$1" 2>/dev/null; then
    return 0
  fi
  if [ "$2" = interactive ]; then
    log "no passwordless sudo for pmset — prompting (install the ansible extra to avoid this)."
    sudo /usr/bin/pmset -a disablesleep "$1" && return 0
  fi
  log "WARNING: could not set disablesleep=$1 (sudoers drop-in missing?)."
  log "         Enable roles/extras/tasks/enabled/84-travel-mode.yml and re-run ansible."
  return 1
}

sleep_override_state() {
  pmset -g | awk '/SleepDisabled/ {print $2}'
}

# ---- connectivity ------------------------------------------------------------
online() { ping -c1 -t5 1.1.1.1 >/dev/null 2>&1; }

# Restore connectivity: walk the preferred SSIDs in order, then power-cycle
# WiFi so macOS auto-joins the highest-priority saved network.
reconnect() {
  local dev=$TRAVEL_MODE_WIFI_DEV ssid
  networksetup -setairportpower "$dev" on >/dev/null 2>&1
  for ssid in ${TRAVEL_MODE_NETWORKS[@]+"${TRAVEL_MODE_NETWORKS[@]}"}; do
    log "internet down — trying $ssid ..."
    networksetup -setairportnetwork "$dev" "$ssid" >/dev/null 2>&1
    sleep 5
    if online; then log "reconnected via $ssid"; return 0; fi
  done
  log "cycling WiFi to force auto-join ..."
  networksetup -setairportpower "$dev" off >/dev/null 2>&1; sleep 3
  networksetup -setairportpower "$dev" on  >/dev/null 2>&1; sleep 8
  if online; then log "reconnected via auto-join"; return 0; fi
  log "still offline — will retry next cycle."
  return 1
}

# ---- worker -------------------------------------------------------------------
# The long-running loop: hold the system awake with caffeinate and probe the
# internet every cycle (the ping doubles as a hotspot keep-alive). Shared by
# `run` (foreground) and the LaunchAgent (`_worker`).
worker() {
  caffeinate -ims &
  local caff=$!
  trap 'kill '"$caff"' 2>/dev/null; exit 0' INT TERM
  trap 'kill '"$caff"' 2>/dev/null' EXIT
  log "worker up (pid $$, caffeinate $caff); probing every ${TRAVEL_MODE_INTERVAL}s."
  while true; do
    online || reconnect
    # `sleep & wait` instead of plain sleep: bash defers trap handlers until a
    # foreground child exits, but `wait` is interruptible — so stop signals
    # take effect immediately instead of after up to a full interval.
    sleep "$TRAVEL_MODE_INTERVAL" & wait $!
  done
}

# ---- LaunchAgent plumbing ------------------------------------------------------
agent_loaded() { launchctl print "gui/$(id -u)/${LABEL}" >/dev/null 2>&1; }

write_plist() {
  mkdir -p "${HOME}/Library/LaunchAgents" "$(dirname "$LOG_FILE")"
  cat > "$PLIST" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>Label</key><string>${LABEL}</string>
  <key>ProgramArguments</key>
  <array>
    <string>${SCRIPT_PATH}</string>
    <string>_worker</string>
  </array>
  <key>RunAtLoad</key><true/>
  <key>KeepAlive</key><true/>
  <key>StandardOutPath</key><string>${LOG_FILE}</string>
  <key>StandardErrorPath</key><string>${LOG_FILE}</string>
</dict>
</plist>
EOF
}

# ---- subcommands ---------------------------------------------------------------
# Foreground cleanup. The worker runs as a child process so its caffeinate
# trap can't clobber ours; here we stop it, then restore lid-close sleep.
RUN_WORKER_PID=""
run_cleanup() {
  trap - EXIT INT TERM
  if [ -n "$RUN_WORKER_PID" ]; then
    kill "$RUN_WORKER_PID" 2>/dev/null
    wait "$RUN_WORKER_PID" 2>/dev/null
  fi
  sleep_override 0 interactive >/dev/null 2>&1
  echo
  log "lid-close sleep restored."
  exit 0
}

cmd_run() {
  log "system + lid stay awake, display sleeps/locks, internet auto-recovers. Ctrl-C to stop."
  sleep_override 1 interactive || log "continuing without lid-close override."
  worker &
  RUN_WORKER_PID=$!
  trap run_cleanup EXIT INT TERM
  wait "$RUN_WORKER_PID"
}

cmd_start() {
  if agent_loaded; then
    log "already running (launchctl gui/$(id -u)/${LABEL})."
    return 0
  fi
  sleep_override 1 quiet || log "continuing without lid-close override."
  write_plist
  if launchctl bootstrap "gui/$(id -u)" "$PLIST"; then
    log "started as LaunchAgent ${LABEL} (launchd restarts it if it dies)."
    log "logs: $LOG_FILE — stop with: travel-mode stop"
  else
    log "ERROR: launchctl bootstrap failed."
    sleep_override 0 quiet >/dev/null 2>&1
    return 1
  fi
}

cmd_stop() {
  if agent_loaded; then
    launchctl bootout "gui/$(id -u)/${LABEL}"
    # bootout is asynchronous — wait for the job to actually disappear so a
    # follow-up `status` (or restart) sees the truth.
    local _i
    for _i in 1 2 3 4 5 6 7 8 9 10; do
      agent_loaded || break
      sleep 0.5
    done
    if agent_loaded; then
      log "WARNING: service still tearing down after 5s."
    else
      log "service stopped."
    fi
  else
    log "service not running."
  fi
  rm -f "$PLIST"
  sleep_override 0 quiet && log "lid-close sleep restored."
}

cmd_status() {
  if agent_loaded; then
    log "service: running (gui/$(id -u)/${LABEL})"
  else
    log "service: not running"
  fi
  if online; then log "internet: online"; else log "internet: OFFLINE"; fi
  log "lid-close sleep override (SleepDisabled): $(sleep_override_state)"
  local nets="${TRAVEL_MODE_NETWORKS[*]:-"(none — auto-join only)"}"
  log "wifi dev: ${TRAVEL_MODE_WIFI_DEV}; preferred networks: ${nets}"
}

cmd_logs() {
  [ -f "$LOG_FILE" ] || { log "no log file yet ($LOG_FILE)."; return 1; }
  tail -n 50 -f "$LOG_FILE"
}

case "${1:-}" in
  run)     cmd_run ;;
  start)   cmd_start ;;
  stop)    cmd_stop ;;
  status)  cmd_status ;;
  logs)    cmd_logs ;;
  _worker) worker ;;
  *)
    echo "usage: travel-mode {run|start|stop|status|logs}"
    echo "  run     foreground; Ctrl-C stops and reverts everything"
    echo "  start   background service (launchd; survives closing the terminal)"
    echo "  stop    stop the service and restore normal sleep"
    echo "  status  service / connectivity / sleep-override state"
    echo "  logs    tail the service log"
    exit 1
    ;;
esac
