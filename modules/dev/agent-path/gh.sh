#!/bin/sh
# Agent PATH shim (see agent-path.nix): a successful `gh pr create` also opens
# the new PR in the browser. Everything else goes straight to the real gh.

# Drop this directory from PATH so the `gh` below is the real one.
self=$(dirname "$0")
PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -vxF "$self" | paste -sd: -)
export PATH

if [ "${1:-}" = pr ] && [ "${2:-}" = create ]; then
  out=$(gh "$@")
  status=$?
  [ -z "$out" ] || printf '%s\n' "$out"
  [ "$status" -eq 0 ] || exit "$status"
  # `--web` already opened it and prints no URL.
  url=$(printf '%s\n' "$out" | grep -Eo 'https://[^[:space:]]+/pull/[0-9]+' | tail -n 1)
  if [ -n "$url" ]; then
    gh pr view "$url" --web >&2 || echo "gh (agent shim): could not open $url" >&2
  fi
  exit 0
fi

exec gh "$@"
