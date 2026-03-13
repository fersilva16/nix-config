#!/usr/bin/env bash

# Flexoki light theme colors via ANSI escapes
# Using tput/ANSI for terminal coloring inside the popup

BOLD=$(tput bold)
DIM=$(tput dim)
RESET=$(tput sgr0)
CYAN=$(tput setaf 6)
YELLOW=$(tput setaf 3)
MAGENTA=$(tput setaf 5)

header() {
  echo "${BOLD}${CYAN}$1${RESET}"
}

key() {
  printf "  ${YELLOW}%-20s${RESET} %s\n" "$1" "$2"
}

sep() {
  echo ""
}

SEPARATOR="${DIM}$(printf '%0.s─' $(seq 1 58))${RESET}"

# Build content into a temp file (avoids mapfile/bash-ism issues)
CONTENT=$(mktemp)
trap 'rm -f "$CONTENT"' EXIT

{
  echo "${BOLD}${MAGENTA}  tmux cheatsheet${RESET}    ${DIM}prefix = Ctrl+Space${RESET}"
  echo "$SEPARATOR"
  sep

  header "Sessions"
  key "prefix s" "list sessions"
  key "prefix d" "detach"
  key "prefix \$" "rename session"
  key ":new -s name" "new session"
  key ":kill-session -t X" "delete session X"
  key "x (in prefix s)" "delete hovered session"
  sep

  header "Windows"
  key "prefix c" "new window"
  key "prefix ," "rename window"
  key "prefix n / p" "next / previous window"
  key "prefix 1-9" "go to window #"
  key "prefix &" "close window"
  key "prefix w" "window preview"
  sep

  header "Panes"
  key "prefix %" "split vertical"
  key "prefix \"" "split horizontal"
  key "prefix arrow" "move between panes"
  key "prefix z" "toggle zoom"
  key "prefix x" "close pane"
  key "prefix !" "pane → window"
  key "prefix {  /  }" "swap pane left / right"
  key "prefix space" "cycle layouts"
  sep

  header "Copy Mode (vi)"
  key "prefix [" "enter copy mode"
  key "v" "begin selection"
  key "y" "yank selection"
  key "prefix ]" "paste"
  key "/" "search forward"
  key "?" "search backward"
  sep

  header "Multi-Monitor"
  key "prefix g" "group session (new view)"
  key "prefix G" "leave grouped session"
  sep

  header "Remote Access"
  key "prefix Ctrl+R" "toggle remote mode"
  sep

  header "Misc"
  key "prefix ?" "this cheatsheet"
  key "prefix n" "notification panel"
  key "prefix N" "jump to last notification"
  key "prefix :" "command prompt"
  key "prefix t" "show clock"
  key "prefix ~" "show messages"
} > "$CONTENT"

TOTAL=$(wc -l < "$CONTENT")

# Scrollable viewer
TOP=1

draw() {
  local height visible
  height=$(tput lines)
  visible=$((height - 1))

  clear
  sed -n "${TOP},$((TOP + visible - 1))p" "$CONTENT"

  # Footer
  tput cup $((height - 1)) 0
  printf '%s  j/k scroll  esc/q close%s' "${DIM}" "${RESET}"
}

draw

while true; do
  read -rsn1 key

  # Handle escape sequences (esc key sends \e, arrow keys send \e[A etc.)
  if [[ "$key" == $'\e' ]]; then
    # Read any remaining bytes of escape sequence (non-blocking)
    read -rsn2 -t 0.01 extra || true
    # If no extra bytes, it was a bare Esc press
    if [[ -z "$extra" ]]; then
      exit 0
    fi
    # Otherwise ignore the escape sequence (arrow keys etc.)
    continue
  fi

  case "$key" in
    j)
      height=$(tput lines)
      visible=$((height - 1))
      if ((TOP + visible <= TOTAL)); then
        TOP=$((TOP + 1))
        draw
      fi
      ;;
    k)
      if ((TOP > 1)); then
        TOP=$((TOP - 1))
        draw
      fi
      ;;
    q) exit 0 ;;
  esac
done
