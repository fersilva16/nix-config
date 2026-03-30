#!/usr/bin/env bash

# tmux-agent-prompt: Minimal prompt dialog for spawning opencode agents
# Escape or Ctrl+C dismisses, Enter submits.

set -eu
trap 'exit 0' INT

PANE_PATH="$1"

printf ' 󰚩 agent: '

PROMPT=""
while IFS= read -rsn1 char; do
  if [[ "$char" == $'\e' ]]; then
    read -rsn5 -t 0.01 _ 2>/dev/null || true
    exit 0
  fi

  [[ "$char" == "" ]] && break

  if [[ "$char" == $'\x7f' || "$char" == $'\b' ]]; then
    if [[ -n "$PROMPT" ]]; then
      PROMPT="${PROMPT%?}"
      printf '\b \b'
    fi
    continue
  fi

  PROMPT+="$char"
  printf '%s' "$char"
done

[[ -z "$PROMPT" ]] && exit 0

printf '\n'
exec tmux-spawn-agent "$PANE_PATH" "$PROMPT"
