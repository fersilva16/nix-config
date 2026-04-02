#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

get_tmux_option() {
  local option="$1"
  local default_value="$2"
  local option_value
  option_value="$(tmux show-option -gqv "$option")"
  if [[ -z "$option_value" ]]; then
    echo "$default_value"
  else
    echo "$option_value"
  fi
}

main() {
  local theme
  theme="$(get_tmux_option "@flexoki-theme" "")"

  if [[ -z "$theme" ]]; then
    theme="light"
  fi

	tmux source-file "$CURRENT_DIR/flexoki-${theme}.tmuxtheme"
  tmux source-file "$CURRENT_DIR/flexoki-bar.conf"
}

main
