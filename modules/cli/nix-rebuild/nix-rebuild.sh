#!/usr/bin/env bash

usage="usage: nix-rebuild [vega|polaris|altair] [rebuild args...]"
remote=/run/current-system/sw/bin/nix-rebuild
repo="$HOME/nix-config"

target="${1:-$here}"
[[ $# -gt 0 ]] && shift

# The machine that builds each host. altair is too small to build itself.
case "$target" in
  vega) builder=vega ;;
  polaris | altair) builder=polaris ;;
  -h | --help)
    echo "$usage"
    exit 0
    ;;
  *)
    echo "$usage" >&2
    exit 2
    ;;
esac

warn() { printf '\033[33m%s\033[0m\n' "$*" >&2; }
alarm() { printf '\a\033[1;31m%s\033[0m\n' "$*" >&2; }

# main with nothing uncommitted follows origin, so a forgotten pull never
# deploys an old main. Any other state builds as it is.
sync_repo() {
  local branch
  branch="$(git -C "$repo" branch --show-current)"
  if [[ $branch == main && -z "$(git -C "$repo" status --porcelain)" ]]; then
    git -C "$repo" pull -q --ff-only || warn "Could not pull main; building it as it is."
  else
    warn "Building ${branch:-a detached HEAD} in $repo as it is, without a pull."
  fi
}

build_here() {
  sync_repo
  if [[ $target == vega ]]; then
    exec sudo darwin-rebuild switch --flake "$repo#vega" "$@"
  elif [[ $target == "$here" ]]; then
    exec sudo nixos-rebuild switch --flake "$repo#$target" "$@"
  else
    exec nixos-rebuild switch --flake "$repo#$target" --target-host "$target" --sudo "$@"
  fi
}

alive() { ssh -o ConnectTimeout=5 -o BatchMode=yes "$1" true 2>/dev/null; }

if [[ $here == "$builder" || $here == "$target" ]]; then
  build_here "$@"
fi

if alive "$builder"; then
  exec ssh -t "$builder" "$remote" "$target" "$@"
fi

alarm "$builder is not reachable, so it cannot build $target."
if [[ $builder != "$target" ]] && alive "$target"; then
  read -r -p "Build $target on $target itself instead? [y/N] " answer
  if [[ $answer == [yY]* ]]; then
    exec ssh -t "$target" "$remote" "$target" "$@"
  fi
fi
exit 1
