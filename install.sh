#!/usr/bin/env bash

set -euo pipefail

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
VERSION=$(cat "$here/VERSION")

PREFIX="${PREFIX:-/usr/local}"
DESTDIR="${DESTDIR:-}"
OS_RELEASE="${OS_RELEASE:-/etc/os-release}"
EXTRA_SHADERS=()
ROFI_PROMPT=""
WAYBAR_SIGNAL=""
UNINSTALL=0
config_given=""

usage() {
  cat <<EOF
install.sh — install screen-shader $VERSION and its effects

Each run converges the prefix to exactly the flags given: re-running without a flag
undoes what that flag installed, the way unsetting a Nix option does on rebuild.

  PREFIX=$PREFIX (override with PREFIX=... or --prefix DIR)
  DESTDIR=${DESTDIR:-<empty>} (override with DESTDIR=... or --destdir DIR for staging)

  -h, --help            show this help and exit
  -v, --version         print the version and exit
      --prefix DIR      install prefix (default: /usr/local)
      --destdir DIR     staging root: files land under DESTDIR/PREFIX
      --uninstall       remove everything a previous install wrote, by its manifest
      --extra-shader FILE
                        install an additional .frag effect; repeatable
      --rofi-prompt STR bake a default picker prompt into bin/rofi-shader
      --waybar-signal N bake a default waybar RT signal into bin/screen-shader

The scripts and the shaders go to \$PREFIX/share/screen-shader, and \$PREFIX/bin gets
symlinks to screen-shader and rofi-shader — the modi stays off PATH, because rofi is
what runs it. The scripts resolve their own location through the symlink, so both the
effects and each other are found without any generated path. --rofi-prompt and
--waybar-signal replace a symlink with a two-line wrapper exporting the default — your
own environment still wins, like Nix's --set-default. A prompt set this way reaches the
modi through rofi-shader; composing the modi into a rofi of your own reads
ROFI_SHADER_PROMPT from your session instead.

Runtime environment (read by the installed scripts, not this script):
  SCREEN_SHADER_DIR       effects directory (default: beside the manager)
  SCREEN_SHADER_USER_DIR  writable effects directory for \`add\`
  SCREEN_SHADER_STATE     durable state file
  WAYBAR_SHADER_SIGNAL    RT signal to poke waybar with after a change
  ROFI_SHADER_PROMPT      picker prompt
  SCREEN_SHADER, SCREEN_SHADER_MODI, SCREEN_SHADER_UI
                          paths the three scripts use to find each other
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
    --extra-shader)
      EXTRA_SHADERS+=("${2:?file required by $1}")
      config_given="$1"
      shift 2
      ;;
    --rofi-prompt)
      ROFI_PROMPT="${2:?value required by $1}"
      config_given="$1"
      shift 2
      ;;
    --waybar-signal)
      WAYBAR_SIGNAL="${2:?value required by $1}"
      config_given="$1"
      shift 2
      ;;
    --uninstall)
      UNINSTALL=1
      shift
      ;;
    -v | --version)
      echo "screen-shader $VERSION"
      exit 0
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

if [[ "$PREFIX" != /* ]]; then
  echo "install.sh: PREFIX must be absolute: $PREFIX" >&2
  exit 1
fi
if ((UNINSTALL)) && [[ -n "$config_given" ]]; then
  echo "install.sh: --uninstall does not combine with $config_given" >&2
  exit 1
fi
if [[ -n "$WAYBAR_SIGNAL" && ! "$WAYBAR_SIGNAL" =~ ^[0-9]+$ ]]; then
  echo "install.sh: --waybar-signal takes a number: $WAYBAR_SIGNAL" >&2
  exit 1
fi

root="${DESTDIR%/}$PREFIX"
share_runtime="$PREFIX/share/screen-shader"
share="${DESTDIR%/}$share_runtime"
manifest="$share/install-manifest"

# --- uninstall -------------------------------------------------------------------------

if ((UNINSTALL)); then
  if [[ ! -f "$manifest" ]]; then
    # Installs made before the manifest existed (screen-shader <= 1.1.0): the fixed
    # list those versions wrote. Drop this arm one release later
    rm -f \
      "$root/bin/screen-shader" \
      "$root/bin/rofi-shader" \
      "$root/share/bash-completion/completions/screen-shader" \
      "$root/share/zsh/site-functions/_screen-shader"
    rm -rf "$share"
    echo "removed screen-shader from $root"
    exit 0
  fi
  while IFS= read -r path; do
    [[ -z "$path" || "$path" == \#* ]] && continue
    rm -f "${DESTDIR%/}$path"
  done <"$manifest"
  rm -f "$manifest"
  rmdir "$share/shaders" "$share" 2>/dev/null || true
  echo "removed screen-shader from $root"
  exit 0
fi

# --- preflight: refuse loudly, install nothing ----------------------------------------
# The manager's own tools have to exist for the installed scripts to run; the session's
# tools — the compositor, the picker, the notifier — only have to exist when a session
# uses them, so their absence is a warning and the install proceeds

missing=()
absent=()

need() { command -v "$1" >/dev/null 2>&1 || missing+=("$1"); }
want() { command -v "$1" >/dev/null 2>&1 || absent+=("$1"); }

need install
need gawk
need flock
need pkill
want hyprctl
want rofi
want notify-send

for file in "${EXTRA_SHADERS[@]}"; do
  if [[ ! -r "$file" ]]; then
    echo "install.sh: --extra-shader file not readable: $file" >&2
    exit 1
  fi
  if [[ "$file" != *.frag ]]; then
    echo "install.sh: --extra-shader wants a .frag file: $file" >&2
    exit 1
  fi
done

distro_id() {
  sed -n 's/^ID\(_LIKE\)\?=//p' "$OS_RELEASE" 2>/dev/null | tr -d '"' | tr '\n' ' '
}

# Missing commands become the distribution's own package names, printed as runnable
# `  $ command` lines — the distro tests run exactly these, so a typo here is a red run
pkg_for() {
  case "$1" in
    gawk) echo gawk ;;
    flock) echo util-linux ;;
    pkill)
      case " $(distro_id) " in
        *" arch "* | *" fedora "*) echo procps-ng ;;
        *) echo procps ;;
      esac
      ;;
    *) echo "$1" ;;
  esac
}

if ((${#missing[@]})); then
  pkgs=()
  for command in "${missing[@]}"; do
    pkgs+=("$(pkg_for "$command")")
  done
  {
    printf 'install.sh: missing dependencies:\n'
    printf '  - %s\n' "${missing[@]}"
    case " $(distro_id) " in
      *" arch "*)
        printf '\nInstall them on Arch:\n'
        printf '  $ sudo pacman -S --needed %s\n' "${pkgs[*]}"
        ;;
      *" debian "* | *" ubuntu "*)
        printf '\nInstall them on Debian/Ubuntu:\n'
        printf '  $ sudo apt-get update\n'
        printf '  $ sudo apt-get install %s\n' "${pkgs[*]}"
        ;;
      *" fedora "*)
        printf '\nInstall them on Fedora:\n'
        printf '  $ sudo dnf install %s\n' "${pkgs[*]}"
        ;;
      *)
        printf '\nInstall them with your package manager: %s\n' "${pkgs[*]}"
        ;;
    esac
  } >&2
  exit 1
fi
if ((${#absent[@]})); then
  printf 'install.sh: not found (comes from your session, install proceeds): %s\n' \
    "${absent[@]}" >&2
fi

# --- install ---------------------------------------------------------------------------
# Every file lands in the manifest as its final runtime path (no DESTDIR); paths a
# previous install wrote that this run does not are swept at the end, which is what
# makes the flags declarative

old_paths=()
if [[ -f "$manifest" ]]; then
  mapfile -t old_paths < <(grep -v '^#' "$manifest")
fi

installed=()
rec() { installed+=("${1#"${DESTDIR%/}"}"); }

install -Dm755 "$here/screen-shader.sh" "$share/screen-shader.sh"
rec "$share/screen-shader.sh"
install -Dm755 "$here/rofi-shader.sh" "$share/rofi-shader.sh"
rec "$share/rofi-shader.sh"
install -Dm755 "$here/shader-modi.sh" "$share/shader-modi.sh"
rec "$share/shader-modi.sh"
install -Dm644 "$here/VERSION" "$share/VERSION"
rec "$share/VERSION"
install -d "$share/shaders"
for file in "$here"/shaders/*.frag; do
  install -Dm644 "$file" "$share/shaders/$(basename "$file")"
  rec "$share/shaders/$(basename "$file")"
done
for file in "${EXTRA_SHADERS[@]}"; do
  install -Dm644 "$file" "$share/shaders/$(basename "$file")"
  rec "$share/shaders/$(basename "$file")"
done

# bin entries are relative symlinks, until a flag bakes an environment default — then a
# two-line wrapper takes the symlink's place, with ${VAR:-...} so the caller's own
# environment still wins (the non-Nix analog of wrapProgram --set-default)
install -d "$root/bin"
if [[ -n "$WAYBAR_SIGNAL" ]]; then
  rm -f "$root/bin/screen-shader"
  cat >"$root/bin/screen-shader" <<EOF
#!/bin/sh
export WAYBAR_SHADER_SIGNAL="\${WAYBAR_SHADER_SIGNAL:-$WAYBAR_SIGNAL}"
exec "$share_runtime/screen-shader.sh" "\$@"
EOF
  chmod 755 "$root/bin/screen-shader"
else
  ln -sfn ../share/screen-shader/screen-shader.sh "$root/bin/screen-shader"
fi
rec "$root/bin/screen-shader"
if [[ -n "$ROFI_PROMPT" ]]; then
  rm -f "$root/bin/rofi-shader"
  cat >"$root/bin/rofi-shader" <<EOF
#!/bin/sh
export ROFI_SHADER_PROMPT="\${ROFI_SHADER_PROMPT:-$ROFI_PROMPT}"
exec "$share_runtime/rofi-shader.sh" "\$@"
EOF
  chmod 755 "$root/bin/rofi-shader"
else
  ln -sfn ../share/screen-shader/rofi-shader.sh "$root/bin/rofi-shader"
fi
rec "$root/bin/rofi-shader"

install -Dm644 "$here/completions/screen-shader.bash" "$root/share/bash-completion/completions/screen-shader"
rec "$root/share/bash-completion/completions/screen-shader"
install -Dm644 "$here/completions/_screen-shader" "$root/share/zsh/site-functions/_screen-shader"
rec "$root/share/zsh/site-functions/_screen-shader"

# The declarative sweep: whatever the previous install wrote and this one did not
for path in "${old_paths[@]}"; do
  keep=0
  for now in "${installed[@]}"; do
    [[ "$path" == "$now" ]] && keep=1
  done
  ((keep)) || rm -f "${DESTDIR%/}$path"
done

{
  echo "# screen-shader $VERSION install manifest"
  printf '%s\n' "${installed[@]}"
} >"$manifest"

echo "installed screen-shader $VERSION to $share, linked into $root/bin"
