#!/usr/bin/env bash

usage() {
  echo "usage: realdu [DIR]" >&2
  exit 64
}

[[ $# -le 1 ]] || usage
dir=${1:-.}
case $dir in -h | --help) usage ;; esac
[[ -d $dir ]] || {
  echo "realdu: $dir: not a directory" >&2
  exit 66
}
[[ -r $dir && -x $dir ]] || {
  echo "realdu: $dir: permission denied" >&2
  exit 77
}

# Prints one line per entry of $dir: name, du bytes, unique bytes.
scan() {
  if [[ $(uname -s) == Darwin ]]; then
    realdu-apfs "$dir"
    return
  fi

  shopt -s dotglob nullglob
  local entries=("$dir"/*)
  ((${#entries[@]})) || return 0

  if [[ $(stat -f -c %T "$dir") == btrfs ]]; then
    btrfs filesystem du -s --raw -- "${entries[@]}" | awk 'NR > 1 {
      total = $1; exclusive = $2
      sub(/^ *[0-9]+ +[0-9]+ +[0-9]+ +/, ""); sub(/\/$/, ""); sub(/.*\//, "")
      print $0 "\t" total "\t" exclusive
    }'
  else
    paste <(du -sxlB1 -- "${entries[@]}") <(du -sxB1 -- "${entries[@]}") |
      awk -F'\t' '{ name = $2; sub(/.*\//, "", name); print name "\t" $1 "\t" $3 }'
  fi
}

scan | sort -t $'\t' -k3,3nr -k2,2nr | awk -F'\t' '
  function human(b,   units, i) {
    split("B K M G T P", units, " ")
    for (i = 1; b >= 1024 && i < 6; i++) b /= 1024
    return i == 1 ? sprintf("%d%s", b, units[i]) : sprintf("%.1f%s", b, units[i])
  }
  BEGIN { printf "%8s  %8s  %s\n", "UNIQUE", "DU", "NAME" }
  { unique += $3; total += $2; printf "%8s  %8s  %s\n", human($3), human($2), $1 }
  END { printf "%8s  %8s  %s\n", human(unique), human(total), "(sum)" }
'
