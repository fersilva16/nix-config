#!/usr/bin/env bash

CURRENT_DIR="$( cd "$( dirname "${BASH_SOURCE[0]}" )" && pwd )"

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
