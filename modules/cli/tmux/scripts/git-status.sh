#!/usr/bin/env bash

# Flexoki light theme colors
BG="#f2f0e5"
FG="#100f0f"
FG_MUTED="#6f6e69"
RED="#d14d41"
GREEN="#879a39"
YELLOW="#d0a215"
MAGENTA="#8b7ec8"

RESET="#[fg=${FG},bg=${BG},nobold,noitalics,nounderscore,nodim]"

cd "$1" || exit 1

BRANCH=$(git rev-parse --abbrev-ref HEAD 2>/dev/null)
[[ -z "$BRANCH" ]] && exit 0

STATUS=$(git status --porcelain 2>/dev/null | grep -cE "^(M| M)")

SYNC_MODE=0

if [[ ${#BRANCH} -gt 25 ]]; then
  BRANCH="${BRANCH:0:25}…"
fi

STATUS_CHANGED=""
STATUS_INSERTIONS=""
STATUS_DELETIONS=""
STATUS_UNTRACKED=""

if [[ $STATUS -ne 0 ]]; then
  read -r CHANGED_COUNT INSERTIONS_COUNT DELETIONS_COUNT < <(
    git diff --numstat 2>/dev/null | awk 'NF==3 {changed+=1; ins+=$1; del+=$2} END {printf("%d %d %d", changed, ins, del)}'
  )
  SYNC_MODE=1
fi

UNTRACKED_COUNT="$(git ls-files --other --directory --exclude-standard 2>/dev/null | wc -l | tr -d ' ')"

if [[ ${CHANGED_COUNT:-0} -gt 0 ]]; then
  STATUS_CHANGED="${RESET}#[fg=${YELLOW},bg=${BG},bold] ${CHANGED_COUNT} "
fi

if [[ ${INSERTIONS_COUNT:-0} -gt 0 ]]; then
  STATUS_INSERTIONS="${RESET}#[fg=${GREEN},bg=${BG},bold] ${INSERTIONS_COUNT} "
fi

if [[ ${DELETIONS_COUNT:-0} -gt 0 ]]; then
  STATUS_DELETIONS="${RESET}#[fg=${RED},bg=${BG},bold] ${DELETIONS_COUNT} "
fi

if [[ ${UNTRACKED_COUNT:-0} -gt 0 ]]; then
  STATUS_UNTRACKED="${RESET}#[fg=${FG_MUTED},bg=${BG},bold] ${UNTRACKED_COUNT} "
fi

# Determine repository sync status
if [[ $SYNC_MODE -eq 0 ]]; then
  # shellcheck disable=SC1083
  NEED_PUSH=$(git log @{push}.. 2>/dev/null | wc -l | tr -d ' ')
  if [[ ${NEED_PUSH:-0} -gt 0 ]]; then
    SYNC_MODE=2
  elif [[ -f .git/FETCH_HEAD ]]; then
    LAST_FETCH=$(stat -c %Y .git/FETCH_HEAD 2>/dev/null || stat -f %m .git/FETCH_HEAD 2>/dev/null || echo 0)
    NOW=$(date +%s)

    if [[ $((NOW - LAST_FETCH)) -gt 300 ]]; then
      git fetch --atomic origin --negotiation-tip=HEAD 2>/dev/null
    fi

    REMOTE_DIFF="$(git diff --numstat "${BRANCH}" "origin/${BRANCH}" 2>/dev/null)"
    if [[ -n $REMOTE_DIFF ]]; then
      SYNC_MODE=3
    fi
  fi
fi

# Set the status indicator based on the sync mode
case "$SYNC_MODE" in
1)
  REMOTE_STATUS="$RESET#[bg=${BG},fg=${RED},bold] 󱓎"
  ;;
2)
  REMOTE_STATUS="$RESET#[bg=${BG},fg=${RED},bold] 󰛃"
  ;;
3)
  REMOTE_STATUS="$RESET#[bg=${BG},fg=${MAGENTA},bold] 󰛀"
  ;;
*)
  REMOTE_STATUS="$RESET#[bg=${BG},fg=${GREEN},bold] "
  ;;
esac

echo "$REMOTE_STATUS $RESET$BRANCH $STATUS_CHANGED$STATUS_INSERTIONS$STATUS_DELETIONS$STATUS_UNTRACKED"
