#!/usr/bin/env bash

# The rofi script-modi: rofi runs this on every selection, nobody runs it by hand. It is
# installed off PATH and rofi-shader hands rofi its absolute path
set -euo pipefail

# Everything goes through the UI layer rather than straight to the manager: it passes
# stdout through untouched, and it is the one place that turns a message into a popup
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
UI="${SCREEN_SHADER_UI:-$(dirname "$SELF")/rofi-shader.sh}"

# Service values of the brightness buttons (not effects) — handled separately
BRIGHT_UP="__bright_up__"
BRIGHT_DOWN="__bright_down__"

# What rofi told us, taken once and then cleared from the environment: everything below
# is a child process, and rofi-shader treats ROFI_RETV as "somebody pointed rofi at me"
selected="${ROFI_INFO:-}"
unset ROFI_RETV ROFI_INFO

# Selection via the info value: brightness buttons adjust soft brightness; effects toggle in/out of the stack
# No exec — reprint the list so rofi stays open; "Normal" clears all, Escape closes
if [[ -n "$selected" ]]; then
  case "$selected" in
    "$BRIGHT_UP") "$UI" bright up ;;
    "$BRIGHT_DOWN") "$UI" bright down ;;
    *) "$UI" effect toggle "$selected" ;;
  esac
fi

# keep-selection: after applying an item rofi redraws the list — without this the
# cursor would jump to the top. With the option the position is kept, so you can
# click effects/brightness in a row without scrolling again (rofi >= 1.7)
printf '\0keep-selection\x1ftrue\n'
# The mode name, set through the script protocol. NOT -display-shader: rofi registers
# that option only for its built-in modes, so for a script modi it is silently ignored
# and the raw mode name shows instead. This way nothing has to be declared in rofi.rasi
printf '\0prompt\x1f%s\n' "${ROFI_SHADER_PROMPT:-📺}"
# The current soft-brightness level goes into the message above the list, updated on every click
printf '\0message\x1fFull-screen effect · brightness %s%%\n' "$("$UI" bright get)"

# Print the effects: visible label + hidden value (info). Active ones are marked with an
# apply number (01. 02. …), a raw one with "raw." and the stack it displaced with
# "(01.)" — see cmd_menu in screen-shader.sh. Right after
# "Normal" (reset) we insert the soft-brightness buttons — different emojis
# (🌕 brighter / 🌑 darker) for clarity; together with keep-selection it's handy to press in a row
while IFS='|' read -r label value; do
  printf '%s\0info\x1f%s\n' "$label" "$value"
  if [[ "$value" == "none" ]]; then
    printf '🌕 Brightness +\0info\x1f%s\n' "$BRIGHT_UP"
    printf '🌑 Brightness −\0info\x1f%s\n' "$BRIGHT_DOWN"
  fi
done < <("$UI" menu)
