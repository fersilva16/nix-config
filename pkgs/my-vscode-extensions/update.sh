#! /usr/bin/env bash
set -eu -o pipefail

function fail() {
  echo "$1" >&2
  exit 1
}

function clean_up() {
  TDIR="${TMPDIR:-/tmp}"

  echo "Script killed, cleaning up tmpdirs: $TDIR/vscode_exts_*" >&2

  rm -rf "$TDIR/vscode_exts_*"
}

function get_vsixpkg() {
  N="$1.$2"

  EXTTMP=$(mktemp -d -t vscode_exts_XXXXXXXX)

  URL="https://$1.gallery.vsassets.io/_apis/public/gallery/publisher/$1/extension/$2/latest/assetbyname/Microsoft.VisualStudio.Services.VSIXPackage"

  curl --silent --show-error --retry 3 --fail -X GET -o "$EXTTMP/$N.zip" "$URL"

  VER=$(jq -r '.version' <(unzip -qc "$EXTTMP/$N.zip" "extension/package.json"))

  SHA=$(nix-hash --flat --base32 --type sha256 "$EXTTMP/$N.zip")

  rm -rf "$EXTTMP"

  cat <<-EOF
  {
    name = "$2";
    publisher = "$1";
    version = "$VER";
    sha256 = "$SHA";
  }
EOF
}

trap clean_up SIGINT

printf '[\n'

grep -v '^ *#' < extensions | while IFS= read -r LINE
do
  OWNER=$(echo "$LINE" | cut -d. -f1)
  EXT=$(echo "$LINE" | cut -d. -f2)

  get_vsixpkg "$OWNER" "$EXT"
done

printf ']\n'
