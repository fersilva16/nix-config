#!/bin/bash

WATCH_DIR="$HOME/ledger"

if [ ! -d "$WATCH_DIR" ]; then
  exit 0
fi

cd "$WATCH_DIR" || exit 1

if [ -n "$(git status --porcelain)" ]; then
  find . -type f -name "*.backup.*" -delete
  git add .
  git commit -m "$(date +%Y-%m-%d)"
  git push origin main
fi
