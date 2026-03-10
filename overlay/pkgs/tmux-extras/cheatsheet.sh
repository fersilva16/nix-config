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

clear
echo "${BOLD}${MAGENTA}  tmux cheatsheet${RESET}    ${DIM}prefix = Ctrl+Space${RESET}"
echo "${DIM}$(printf '%.0s─' {1..50})${RESET}"
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

header "Misc"
key "prefix ?" "this cheatsheet"
key "prefix n" "notification panel"
key "prefix N" "jump to last notification"
key "prefix :" "command prompt"
key "prefix t" "show clock"
key "prefix ~" "show messages"
sep

echo "${DIM}  press q to close${RESET}"

read -rsn1
