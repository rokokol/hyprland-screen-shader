#!/usr/bin/env bash

set -euo pipefail

PREFIX="${PREFIX:-/usr/local}"
DESTDIR="${DESTDIR:-}"

usage() {
  cat <<EOF
install.sh — install screen-shader and its effects

  PREFIX=$PREFIX (override with PREFIX=... or --prefix DIR)
  DESTDIR=${DESTDIR:-<empty>} (override with DESTDIR=... or --destdir DIR for staging)

The scripts and the shaders go to \$PREFIX/share/screen-shader, and \$PREFIX/bin gets
symlinks to screen-shader and rofi-shader — the modi stays off PATH, because rofi is
what runs it. The scripts resolve their own location through the symlink, so both the
effects and each other are found without any generated path
EOF
}

while [[ $# -gt 0 ]]; do
  case "$1" in
    --prefix)
      PREFIX="${2:?directory required}"
      shift 2
      ;;
    --destdir)
      DESTDIR="${2:?directory required}"
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

if [[ -n "$DESTDIR" && "$PREFIX" != /* ]]; then
  echo "install.sh: PREFIX must be absolute when DESTDIR is set: $PREFIX" >&2
  exit 1
fi

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
root="${DESTDIR%/}$PREFIX"
share="$root/share/screen-shader"

install -Dm755 "$here/screen-shader.sh" "$share/screen-shader.sh"
install -Dm755 "$here/rofi-shader.sh" "$share/rofi-shader.sh"
install -Dm755 "$here/shader-modi.sh" "$share/shader-modi.sh"
install -d "$share/shaders"
install -Dm644 -t "$share/shaders" "$here"/shaders/*.frag

install -d "$root/bin"
ln -sfn ../share/screen-shader/screen-shader.sh "$root/bin/screen-shader"
ln -sfn ../share/screen-shader/rofi-shader.sh "$root/bin/rofi-shader"

echo "installed to $share, linked into $root/bin"
