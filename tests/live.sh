#!/usr/bin/env bash
# Drives the real compositor. tests/run.sh cannot: its hyprctl is a shell script that logs
# the arguments, so the suite proves the manager asks for the right shader and nothing about
# whether the session then wears it. Whether the GLSL compiles is a separate question, and
# tests/run.sh answers it offline with glslang — measured on Hyprland 0.56.1, a shader it
# refuses is announced on the on-screen error bar and in nothing a script can read
#
# Nothing here runs in CI: it needs a running Hyprland. Run it by hand before a tag. The
# session's own stack is saved and put back, so nothing is left switched on
#
#   tests/live.sh

set -uo pipefail

HERE=$(cd -- "$(dirname -- "${BASH_SOURCE[0]}")" && pwd)
SS="${SCREEN_SHADER:-$(dirname "$HERE")/screen-shader.sh}"

fails=0
ok() { printf '  ✓ %s\n' "$1"; }

fail() {
  printf '  ✗ %s\n' "$1"
  fails=$((fails + 1))
}

command -v hyprctl >/dev/null || {
  echo "live: hyprctl is not on PATH" >&2
  exit 1
}
hyprctl version >/dev/null 2>&1 || {
  echo "live: no Hyprland answering — this suite needs a running session" >&2
  exit 1
}

# `restore` re-applies the state file, and every `effect set` below rewrites it — so the file
# itself is what has to be put back, or the session keeps whatever effect the loop ended on
STATE="${SCREEN_SHADER_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/screen-shader/state}"
SAVED=$(mktemp)
[[ -r $STATE ]] && cp "$STATE" "$SAVED"
before=$("$SS" status 2>/dev/null)
restore() {
  set +e
  if [[ -s $SAVED ]]; then
    mkdir -p "$(dirname "$STATE")"
    cp "$SAVED" "$STATE"
  else
    rm -f "$STATE"
  fi
  rm -f "$SAVED"
  "$SS" restore >/dev/null 2>&1
}
trap restore EXIT

echo "live Hyprland $(hyprctl version -j | sed -n 's/.*"tag": *"\([^"]*\)".*/\1/p')"
# Every effect is compiled by the real compositor here, and compiling one means wearing it —
# so the screen is repainted once per effect, in front of you. Whether the GLSL compiles is
# checked offline by tests/run.sh; what this cannot check for you is what it looks like
echo "this paints the screen through every effect in turn, then puts your stack back"
echo "a red bar across the top is Hyprland refusing a shader — it says so nowhere else"

slot() { hyprctl getoption decoration:screen_shader -j | sed -n 's/.*"str": *"\([^"]*\)".*/\1/p'; }

for effect in $("$SS" menu | sed 's/.*|//'); do
  "$SS" effect set "$effect" >/dev/null 2>&1
  path=$(slot)
  # none is the menu's way of spelling "clear", so an empty slot is the right answer for it
  if [[ $effect == none ]]; then
    if [[ $path == "[[EMPTY]]" ]]; then
      ok "none: the slot is empty, as it should be"
    else
      fail "none left '$path' in the slot"
    fi
    continue
  fi
  if [[ $path == *"$effect"* || -r $path ]]; then
    ok "$effect: the slot holds a generated shader"
  else
    fail "$effect: the slot holds '$path'"
    continue
  fi
done

"$SS" effect clear >/dev/null 2>&1
# Hyprland has no "unset" for a string option — [[EMPTY]] is the literal it prints for one
if [[ "$(slot)" == "[[EMPTY]]" ]]; then
  ok "clearing puts the slot back to [[EMPTY]]"
else
  fail "after clearing the slot holds '$(slot)'"
fi

"$SS" bright set 0.5 >/dev/null 2>&1
if [[ "$("$SS" bright get)" == 50 ]] && [[ "$(slot)" != "[[EMPTY]]" ]]; then
  ok "brightness alone still generates a shader"
else
  fail "brightness did not reach the slot"
fi
"$SS" bright reset >/dev/null 2>&1

printf '\nputting the session back: %s\n' "$(echo "$before" | tr -d '\n')"
if ((fails)); then
  printf '%d failed\n' "$fails"
  exit 1
fi
printf 'all passed\n'
