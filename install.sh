#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"

usage() {
  cat <<EOF
install.sh — install screen-shader and its effects

  PREFIX=$PREFIX (override with PREFIX=... or --prefix DIR)

The scripts and the shaders go to \$PREFIX/share/screen-shader, and \$PREFIX/bin gets
symlinks to them. The scripts resolve their own location through the symlink, so the
effects are found without any generated path
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      PREFIX="${2:?directory required}"
      shift 2
      ;;
    -h | --help)
      usage
      exit 0
      ;;
    *)
      usage >&2
      exit 1
      ;;
  esac
done

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
share="$PREFIX/share/screen-shader"

install -Dm755 "$here/screen-shader.sh" "$share/screen-shader.sh"
install -Dm755 "$here/rofi-shader.sh" "$share/rofi-shader.sh"
install -d "$share/shaders"
install -Dm644 -t "$share/shaders" "$here"/shaders/*.frag

install -d "$PREFIX/bin"
ln -sfn ../share/screen-shader/screen-shader.sh "$PREFIX/bin/screen-shader"
ln -sfn ../share/screen-shader/rofi-shader.sh "$PREFIX/bin/rofi-shader"

echo "installed to $share, linked into $PREFIX/bin"
