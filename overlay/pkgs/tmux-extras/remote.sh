#!/usr/bin/env bash

# tmux-remote: Toggle "remote access" mode for lid-closed SSH from iPhone.
#
# When enabled:
#   - Prevents sleep on lid close (pmset disablesleep)
#   - Keeps Wi-Fi alive during sleep (pmset womp + powernap)
#   - Enables SSH (Remote Login)
#   - Closes resource-heavy GUI apps to save battery
#   - Stores list of closed apps for restoration on disable
#
# When disabled:
#   - Re-enables normal sleep behavior
#   - Disables SSH
#   - Reopens apps that were closed
#
# Usage: tmux-remote on|off|toggle|status

STATE_FILE="/tmp/tmux-remote-state"
CLOSED_APPS_FILE="/tmp/tmux-remote-closed-apps"

# Apps to close for battery savings (process names as seen by osascript/pkill)
# These are the resource-heavy GUI apps; system utilities are left running.
APPS_TO_CLOSE=(
  # Browsers
  "Firefox"
  "Google Chrome"
  # Chat
  "Slack"
  "Microsoft Teams"
  "Telegram"
  "WhatsApp"
  "Discord"
  # Editors / IDEs
  "Visual Studio Code"
  "Cursor"
  "IntelliJ IDEA CE"
  "Android Studio"
  # Dev tools
  "DBeaver"
  "Linear"
  "Postman"
  "Studio 3T"
  "OrbStack"
  # Media
  "IINA"
  "Spotify"
  "Stremio"
  # Productivity
  "Anki"
  "Anytype"
  "calibre"
  "Figma"
  "LibreOffice"
  "Loom"
  "Microsoft Word"
  "NetNewsWire"
  "Notion Calendar"
  "Obsidian"
  "Spark"
  # Games
  "Steam"
  # Terminal (if running the GUI terminal — you'll SSH in instead)
  "Ghostty"
)

is_active() {
  [[ -f "$STATE_FILE" ]]
}

get_running_apps() {
  # Returns a list of currently running app names (one per line)
  osascript -e 'tell application "System Events" to get name of every process whose background only is false' 2>/dev/null |
    sed 's/, /\n/g'
}

close_apps() {
  local running closed_count=0
  running=$(get_running_apps)

  # Clear previous closed apps list
  : > "$CLOSED_APPS_FILE"

  for app in "${APPS_TO_CLOSE[@]}"; do
    if echo "$running" | grep -qxF "$app"; then
      echo "$app" >> "$CLOSED_APPS_FILE"
      # Graceful quit via osascript
      osascript -e "tell application \"$app\" to quit" 2>/dev/null &
      closed_count=$((closed_count + 1))
    fi
  done

  # Wait for quit signals to be sent
  wait

  echo "$closed_count"
}

reopen_apps() {
  if [[ ! -f "$CLOSED_APPS_FILE" ]]; then
    return
  fi

  local count=0
  while IFS= read -r app; do
    [[ -z "$app" ]] && continue
    open -gja "$app" 2>/dev/null &
    count=$((count + 1))
  done < "$CLOSED_APPS_FILE"

  wait
  rm -f "$CLOSED_APPS_FILE"
  echo "$count"
}

enable_remote() {
  if is_active; then
    echo "Remote access is already enabled"
    return 0
  fi

  # Close GUI apps first (before any sudo prompts)
  local closed
  closed=$(close_apps)

  # Prevent sleep when lid is closed (battery mode)
  sudo pmset -b disablesleep 1

  # Keep network alive during lid-closed operation
  # womp = Wake on Magic Packet (keeps network interface alive)
  # powernap = allows periodic network activity during sleep
  # tcpkeepalive = maintains TCP connections during sleep
  sudo pmset -b womp 1
  sudo pmset -b powernap 1
  sudo pmset -b tcpkeepalive 1

  # Enable SSH daemon via launchctl (avoids Full Disk Access requirement)
  sudo launchctl load -w /System/Library/LaunchDaemons/ssh.plist 2>/dev/null

  # Mark as active
  touch "$STATE_FILE"

  # Notify via tmux
  if [[ -n "$TMUX" ]]; then
    tmux display-message "Remote access ON — closed ${closed} apps — safe to close lid"
    tmux refresh-client -S
  else
    echo "Remote access ON — closed ${closed} apps — safe to close lid"
  fi
}

disable_remote() {
  if ! is_active; then
    echo "Remote access is already disabled"
    return 0
  fi

  # Restore normal sleep behavior
  sudo pmset -b disablesleep 0
  sudo pmset -b womp 0
  sudo pmset -b powernap 0

  # tcpkeepalive is normally on by default, leave it
  sudo pmset -b tcpkeepalive 1

  # Disable SSH daemon via launchctl
  sudo launchctl unload -w /System/Library/LaunchDaemons/ssh.plist 2>/dev/null

  # Remove state file
  rm -f "$STATE_FILE"

  # Reopen apps that were closed
  local reopened
  reopened=$(reopen_apps)

  # Notify via tmux
  if [[ -n "$TMUX" ]]; then
    tmux display-message "Remote access OFF — reopened ${reopened} apps"
    tmux refresh-client -S
  else
    echo "Remote access OFF — reopened ${reopened} apps"
  fi
}

toggle_remote() {
  if is_active; then
    disable_remote
  else
    enable_remote
  fi
}

print_status() {
  if is_active; then
    echo "ACTIVE"
  else
    echo "INACTIVE"
  fi
}

case "${1:-}" in
  on) enable_remote ;;
  off) disable_remote ;;
  toggle) toggle_remote ;;
  status) print_status ;;
  *)
    echo "Usage: tmux-remote on|off|toggle|status"
    exit 1
    ;;
esac
