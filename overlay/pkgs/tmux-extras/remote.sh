#!/usr/bin/env bash

# tmux-remote: Toggle "remote access" mode for lid-closed SSH.
#
# When enabled:
#   - Prevents sleep on lid close (pmset disablesleep)
#   - Keeps Wi-Fi alive during sleep (pmset womp + powernap)
#   - Enables SSH (Remote Login)
#   - Closes resource-heavy GUI apps to save battery
#   - Stores list of closed apps for restoration on disable
#   - Shows Tailscale IP for outside-network access
#
# When disabled:
#   - Re-enables normal sleep behavior
#   - Disables SSH
#   - Reopens apps that were closed
#
# Network access:
#   - LAN: ssh user@<local-ip>
#   - Outside network: ssh user@<tailscale-ip> (requires Tailscale on both ends)
#
# Usage: tmux-remote on|off|toggle|status

STATE_FILE="/tmp/tmux-remote-state"
CLOSED_APPS_FILE="/tmp/tmux-remote-closed-apps"
TAILSCALE_CLI="tailscale"
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

set_starship_config_all_panes() {
  local config="$1"
  local pane_id pane_cmd
  while IFS=: read -r pane_id pane_cmd; do
    if [[ "$pane_cmd" == "fish" ]]; then
      tmux send-keys -t "$pane_id" C-u "set -gx STARSHIP_CONFIG $config" Enter
    fi
  done < <(tmux list-panes -a -F '#{pane_id}:#{pane_current_command}')
}

unset_starship_config_all_panes() {
  local pane_id pane_cmd
  while IFS=: read -r pane_id pane_cmd; do
    if [[ "$pane_cmd" == "fish" ]]; then
      tmux send-keys -t "$pane_id" C-u "set -ge STARSHIP_CONFIG" Enter
    fi
  done < <(tmux list-panes -a -F '#{pane_id}:#{pane_current_command}')
}

get_tailscale_ip() {
  if ! command -v "$TAILSCALE_CLI" &>/dev/null; then
    return 1
  fi
  $TAILSCALE_CLI ip -4 2>/dev/null
}

get_tailscale_status() {
  if ! command -v "$TAILSCALE_CLI" &>/dev/null; then
    echo "not-installed"
    return
  fi
  local state
  state=$($TAILSCALE_CLI status --json 2>/dev/null | sed -n 's/.*"BackendState":[[:space:]]*"\([^"]*\)".*/\1/p')
  echo "${state:-unknown}"
}

get_local_ip() {
  ipconfig getifaddr en0 2>/dev/null || echo "unavailable"
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

  if [[ -n "$TMUX" ]]; then
    tmux set -g status-left "#{?client_prefix,#[fg=#e6e4d9#,bg=#da702c],#[fg=#da702c#,bg=#e6e4d9]} #S "
    tmux setw -g window-status-format "#[bg=#e6e4d9,fg=#6f6e69] #I "
    tmux setw -g window-status-current-format "#[bg=#f2f0e5,fg=#100f0f] #I "
    tmux setw -g automatic-rename off
    for win in $(tmux list-windows -F '#{window_index}'); do
      local pane_cmd
      pane_cmd=$(tmux display-message -t ":$win" -p '#{pane_current_command}')
      tmux rename-window -t ":$win" "$pane_cmd"
    done
    tmux set-environment -g STARSHIP_CONFIG "$HOME/.config/starship-plain.toml"
    set_starship_config_all_panes "$HOME/.config/starship-plain.toml"
  fi

  local ts_status ts_ip local_ip msg
  ts_status=$(get_tailscale_status)
  local_ip=$(get_local_ip)
  msg="Remote ON — closed ${closed} apps"

  if [[ "$ts_status" == "Running" ]]; then
    ts_ip=$(get_tailscale_ip)
    msg="${msg} — LAN: ${local_ip} / Tailscale: ${ts_ip}"
  elif [[ "$ts_status" == "not-installed" ]]; then
    msg="${msg} — LAN only: ${local_ip} (Tailscale not found)"
  else
    msg="${msg} — LAN: ${local_ip} (Tailscale: ${ts_status})"
  fi

  if [[ -n "$TMUX" ]]; then
    tmux display-message "$msg"
    tmux refresh-client -S
  else
    echo "$msg"
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

  # Restore tmux bar to full theme (Nerd Font icons + window names)
  if [[ -n "$TMUX" ]]; then
    tmux set -g status-left "#{?client_prefix,#[fg=#e6e4d9#,bg=#da702c],#[fg=#da702c#,bg=#e6e4d9]} λ #S "
    tmux setw -g window-status-format "#[bg=#e6e4d9,fg=#6f6e69] #I #W "
    tmux setw -g window-status-current-format "#[bg=#f2f0e5,fg=#100f0f] #I #W "
    tmux setw -g automatic-rename on
    tmux set-environment -gu STARSHIP_CONFIG
    unset_starship_config_all_panes
  fi

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
