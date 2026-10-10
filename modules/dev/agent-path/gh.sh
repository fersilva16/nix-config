#!/bin/sh
# Agent PATH shim (see agent-path.nix):
# - Agents never post as Fernando: comments, review comments and their
#   replies, and reviews are refused, whether through gh subcommands or
#   `gh api` (REST writes, GraphQL mutations). PR/issue bodies and every read
#   pass through. A guardrail for agents, not a sandbox.
# - A successful `gh pr create` also opens the new PR in the browser.
# Everything else goes straight to the real gh.

# Drop this directory from PATH so the `gh` below is the real one.
self=$(dirname "$0")
PATH=$(printf '%s' "$PATH" | tr ':' '\n' | grep -vxF "$self" | paste -sd: -)
export PATH

refuse() {
  printf '%s\n' "gh (agent shim): refused $1. Agents never post comments or reviews as Fernando on GitHub; do not work around this. Draft the text and hand it to him to post." >&2
  exit 1
}

# `gh api`: a write to a comment/review endpoint, or a GraphQL mutation that
# adds, edits, deletes, submits or dismisses a comment or review. Scans every
# argument (plus files passed as `key=@file` or `--input file`) instead of
# parsing gh's flags.
check_api() {
  method='' writes='' text='' prev=''
  for a in "$@"; do
    case $prev in
      -X | --method) method=$a ;;
      --input) [ "$a" = - ] || text="$text $(cat -- "$a" 2>/dev/null)" ;;
    esac
    case $a in
      -X?*) method=${a#-X} ;;
      --method=*) method=${a#--method=} ;;
      --input=*) f=${a#--input=} && writes=1 && { [ "$f" = - ] || text="$text $(cat -- "$f" 2>/dev/null)"; } ;;
      -f* | -F* | --field* | --raw-field* | --input) writes=1 ;;
    esac
    case $a in
      *=@*) f=${a#*=@} && { [ "$f" = - ] || text="$text $(cat -- "$f" 2>/dev/null)"; } ;;
    esac
    text="$text $a"
    prev=$a
  done
  method=$(printf '%s' "${method:-${writes:+POST}}" | tr '[:lower:]' '[:upper:]')

  if printf '%s\n' "$@" | grep -qx graphql; then
    if printf '%s' "$text" | grep -q mutation &&
      printf '%s' "$text" | grep -Eq '(add|update|delete|submit|dismiss|minimize)[A-Za-z]*(Comment|Review)'; then
      refuse "a gh api graphql comment/review mutation"
    fi
  elif [ -n "$method" ] && [ "$method" != GET ] && [ "$method" != HEAD ] &&
    printf '%s\n' "$@" | grep -Eq '(^|/)(comments|reviews)(/[0-9]+)?(/(replies|events|dismissals))?/?([?].*)?$'; then
    refuse "gh api $method on a comment/review endpoint"
  fi
}

case "${1:-} ${2:-}" in
  "pr comment" | "issue comment" | "pr review") refuse "gh $1 $2" ;;
  "pr close" | "pr reopen" | "issue close" | "issue reopen")
    for a in "$@"; do
      case $a in
        -c | -c?* | --comment | --comment=*) refuse "gh $1 $2 --comment" ;;
      esac
    done
    ;;
  "api "*) check_api "$@" ;;
esac

if [ "${1:-}" = pr ] && [ "${2:-}" = create ]; then
  out=$(gh "$@")
  status=$?
  [ -z "$out" ] || printf '%s\n' "$out"
  [ "$status" -eq 0 ] || exit "$status"
  # `--web` already opened it and prints no URL.
  url=$(printf '%s\n' "$out" | grep -Eo 'https://[^[:space:]]+/pull/[0-9]+' | tail -n 1)
  # Detached: on linux, xdg-open can exec the browser itself (no Chrome
  # running yet), and gh waits on it, holding the agent's terminal open.
  if [ -n "$url" ]; then
    gh pr view "$url" --web </dev/null >/dev/null 2>&1 &
  fi
  exit 0
fi

exec gh "$@"
