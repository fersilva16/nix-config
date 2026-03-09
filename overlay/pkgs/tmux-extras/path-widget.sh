#!/usr/bin/env bash

# Flexoki light theme colors
BG="#f2f0e5"
FG="#100f0f"
BLUE="#4385be"

RESET="#[fg=${FG},bg=${BG},nobold,noitalics,nounderscore,nodim]"

SHOW_PATH=$(tmux show-option -gv @flexoki-tmux_show_path 2>/dev/null)
PATH_FORMAT=$(tmux show-option -gv @flexoki-tmux_path_format 2>/dev/null)

# Enabled by default; set @flexoki-tmux_show_path to "0" to disable
if [ "${SHOW_PATH}" = "0" ]; then
  exit 0
fi

current_path="${1}"
PATH_FORMAT="${PATH_FORMAT:-relative}"

if [[ ${PATH_FORMAT} == "relative" ]]; then
  current_path="${current_path/#$HOME/~}"
fi

echo "#[fg=${BLUE},bg=${BG}]  ${RESET}${current_path} "
