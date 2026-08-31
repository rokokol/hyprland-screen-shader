#!/usr/bin/env bash
# Distro tests for screen-shader: run install.sh for real, as root, inside a container
# of an actual distribution — the one thing tests/run.sh cannot do. Here the real
# package manager provides the manager's tools, by running the very commands the
# preflight printed when it refused.
#
#   tests/distro.sh              every distribution below
#   tests/distro.sh debian       just one
#
# Needs docker or podman. In CI this runs on push to master, weekly, and by hand — never
# on pull requests: a flaky mirror must not redden someone's change. Images are :latest
# on purpose — the weekly run is the upstream-drift detector, so no assertion may depend
# on what an image happens to carry already
set -euo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
REPO=$(dirname "$HERE")

declare -A IMAGE=(
  [debian]=docker.io/library/debian:latest
  [ubuntu]=docker.io/library/ubuntu:latest
  [arch]=docker.io/library/archlinux:latest
  [fedora]=docker.io/library/fedora:latest
)

INSTALL_FLAGS=()

# Bootstrap: only what the harness itself needs in a minimal image — never a dependency
# the preflight's guidance is supposed to provide, or the guidance test would pass
# because the answer was planted. Arch needs its sync database refreshed (the printed
# pacman -S cannot work against an empty one, and no reader of a refusal is told to
# type the refresh); fedora's image strips the diff and find the test suite itself uses
declare -A BOOTSTRAP=(
  [debian]=':'
  [ubuntu]=':'
  [arch]='pacman -Sy --noconfirm --needed diffutils'
  [fedora]='dnf install -y -q diffutils findutils'
)

smoke() { # runs inside the container after a successful install
  local prefix="$1"
  "$prefix/bin/screen-shader" --version | grep -qxF "screen-shader $(cat VERSION)"
  # The menu needs no compositor — hyprctl is only reached by an apply
  "$prefix/bin/screen-shader" menu | grep -qF 'Grayscale|grayscale'
  # The whole behaviour suite against the installed copy, hyprctl stubbed
  SCREEN_SHADER="$prefix/bin/screen-shader" ./tests/run.sh >/dev/null
}

# ======================================================================================
# host half: find an engine, pull fresh, re-execute this script inside the container
# ======================================================================================

if [[ "${1:-}" != "--inside" ]]; then
  engine=""
  for candidate in "${CONTAINER_ENGINE:-}" docker podman; do
    [[ -n "$candidate" ]] || continue
    if command -v "$candidate" >/dev/null && "$candidate" info >/dev/null 2>&1; then
      engine="$candidate"
      break
    fi
  done
  if [[ -z "$engine" ]]; then
    echo "tests/distro.sh: needs a working docker or podman" >&2
    exit 1
  fi

  wanted=("$@")
  ((${#wanted[@]})) || wanted=(debian ubuntu arch fedora)

  fails=0
  for distro in "${wanted[@]}"; do
    image="${IMAGE[$distro]:-}"
    if [[ -z "$image" ]]; then
      echo "tests/distro.sh: no such distribution: $distro" >&2
      exit 1
    fi
    printf '\n== %s (%s)\n' "$distro" "$image"
    # One retry on the pull: a mirror hiccup is not a verdict on anything
    "$engine" pull -q "$image" >/dev/null || "$engine" pull -q "$image" >/dev/null
    # The checkout goes in read-only — the run must not be able to edit it
    if ! "$engine" run --rm -v "$REPO:/src:ro" "$image" \
      bash /src/tests/distro.sh --inside "$distro"; then
      printf '  %s: FAILED\n' "$distro"
      fails=$((fails + 1))
    else
      printf '  %s: passed\n' "$distro"
    fi
  done
  ((fails)) && exit 1
  echo
  echo "all distributions passed"
  exit 0
fi

# ======================================================================================
# container half
# ======================================================================================

distro="$2"

say() { printf '\n  -- %s\n' "$1"; }
die() {
  printf '  !! %s\n' "$1" >&2
  exit 1
}

say "bootstrap ($distro)"
bash -c "${BOOTSTRAP[$distro]}" >/dev/null

# The checkout is mounted read-only; work on a copy a package manager cannot be blamed for
cp -r /src /work
cd /work

prefix=/usr/local
bin_path="$prefix/bin/screen-shader"
share_dir="$prefix/share/screen-shader"

say "a relative PREFIX is rejected"
! PREFIX=usr ./install.sh "${INSTALL_FLAGS[@]}" >/dev/null 2>&1 ||
  die "install.sh accepted a relative PREFIX"

say "install, running the printed guidance when the preflight refuses"
rc=0
out=$(./install.sh "${INSTALL_FLAGS[@]}" 2>&1) || rc=$?
if ((rc != 0)); then
  # The refusal must be complete and clean: name what is missing, write nothing
  printf '%s\n' "$out" | grep -q 'missing dependencies' ||
    die "the refusal did not say what is missing: $out"
  [[ ! -e "$bin_path" && ! -e "$share_dir" ]] ||
    die "a refused install left files behind"
  printf '%s\n' "$out" | grep -qE 'command not found|: line [0-9]' &&
    die "the preflight listed what is missing and then carried on: $out"

  # Runnable guidance lines are `  $ command`; they are run exactly as printed.
  # Non-interactivity is arranged around the command — DEBIAN_FRONTEND, yes on stdin —
  # never inside it: the printed line has no -y because a human reads it
  commands=$(printf '%s\n' "$out" | sed -n 's/^  \$ //p')
  if [[ -z "$commands" ]]; then
    echo "::notice title=screen-shader distro test::SKIP on $distro — guidance is manual-only"
    printf '  SKIP: no runnable guidance on %s\n' "$distro"
    exit 0
  fi
  # The container is root and none of these images ships sudo. Answered with a shim, not
  # by editing the line: a sudo can sit mid-pipeline (| sudo tee) where stripping a
  # prefix cannot reach, and an edited line is no longer the line the reader was given
  if ! command -v sudo >/dev/null; then
    printf '#!/bin/sh\nexec "$@"\n' >/usr/local/bin/sudo
    chmod +x /usr/local/bin/sudo
  fi
  export DEBIAN_FRONTEND=noninteractive
  while IFS= read -r cmd; do
    printf '  running printed guidance: %s\n' "$cmd"
    # yes answers "y" to [Y/n]-style prompts; dnf treats an empty answer as No. Fed by
    # process substitution, not a pipe: pipefail would turn yes's own SIGPIPE death —
    # normal for a command that never reads stdin — into a failed pipeline
    bash -c "$cmd" < <(yes 2>/dev/null) || die "printed guidance failed: $cmd"
  done <<<"$commands"

  say "install succeeds once the guidance has been followed"
  ./install.sh "${INSTALL_FLAGS[@]}" || die "install failed after following the guidance"
else
  echo "  (every dependency was already present — the refusal path ran elsewhere)"
fi

say "the installed tool answers"
[[ -e "$bin_path" ]] || die "no $bin_path after install"
[[ -f "$share_dir/install-manifest" ]] || die "no install-manifest after install"
./install.sh --help >/dev/null || die "--help failed"
smoke "$prefix" || die "smoke test failed"

say "uninstall removes exactly what the manifest names"
mapfile -t manifest_paths < <(grep -v '^#' "$share_dir/install-manifest")
./install.sh --uninstall "${INSTALL_FLAGS[@]}" || die "--uninstall failed"
for path in "${manifest_paths[@]}"; do
  [[ ! -e "$path" && ! -L "$path" ]] || die "uninstall left $path behind"
done
[[ ! -e "$share_dir" ]] || die "uninstall left $share_dir behind"

say "a second uninstall is quiet and succeeds"
./install.sh --uninstall "${INSTALL_FLAGS[@]}" >/dev/null || die "uninstall is not idempotent"

echo
echo "  $distro: full cycle passed"
