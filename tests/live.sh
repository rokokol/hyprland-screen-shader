#!/usr/bin/env bash
# Drives the real compositor. tests/run.sh cannot: its hyprctl is a shell script that logs
# the arguments, so the suite proves the manager asks for the right shader and nothing about
# whether Hyprland accepts it. A shader that fails to compile is dropped silently — the slot
# reads back as set either way — so the only witness is the compositor's own log
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

LOG="$XDG_RUNTIME_DIR/hypr/${HYPRLAND_INSTANCE_SIGNATURE:?no instance signature}/hyprland.log"
[[ -r $LOG ]] || {
  echo "live: cannot read $LOG" >&2
  exit 1
}

# Whatever the session had, restored on the way out — including a stack this suite replaced
before=$("$SS" status 2>/dev/null)
restore() {
  set +e
  "$SS" restore >/dev/null 2>&1
}
trap restore EXIT

# The compositor prints a shader failure once, when it compiles it, so only the lines
# arriving from here on say anything about what this run asked for
mark=$(wc -l <"$LOG")
since() { tail -n "+$((mark + 1))" "$LOG"; }

echo "live Hyprland $(hyprctl version -j | sed -n 's/.*"tag": *"\([^"]*\)".*/\1/p')"
# Every effect has to be compiled by the real compositor for this to be worth running, and
# compiling one means wearing it — so the screen is repainted once per effect, in front of you
echo "this paints the screen through every effect in turn, then puts your stack back"

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
  # A shader that does not compile leaves the screen untouched and says so in the log
  if since | grep -iE "shader|glsl" | grep -qiE "error|failed"; then
    fail "$effect: the compositor refused the shader"
    since | grep -iE "shader|glsl" | tail -3 | sed 's/^/      /'
  else
    ok "$effect: no compile error in the log"
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
