#!/usr/bin/env bash
# Print the nearest git repo root for a given directory.
# Falls back to the directory itself if not inside a git repo.
dir="${1:-.}"
cd "$dir" && git rev-parse --show-toplevel 2>/dev/null || echo "$dir"
