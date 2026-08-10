#!/usr/bin/env bash

# The UI layer, and the only executable meant for a keybinding, a bar or a shell. Two
# jobs: open the picker, and put a popup on what screen-shader has to say. The manager
# writes plain text to stderr and knows nothing about notification daemons
set -euo pipefail

MODE="shader"
# Both fall back to a sibling of this script, which is where a plain install puts them;
# under Nix the wrapper sets them to absolute store paths
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
SS="${SCREEN_SHADER:-$(dirname "$SELF")/screen-shader.sh}"
MODI="${SCREEN_SHADER_MODI:-$(dirname "$SELF")/shader-modi.sh}"

# One synchronous tag for everything: holding the brightness key updates a single popup
# instead of pushing a queue of them into the feed
notify() { # $1 = urgency, $2 = title, $3 = body
  local body="$3"
  # mako and most other daemons parse the body as Pango markup, and ours carries effect
  # labels and file paths — one stray & or < and the message never renders. Ampersand
  # first, or the later escapes get escaped too; and \& in the replacement because a bare
  # one means "whatever matched" since bash 5.2
  body="${body//&/\&amp;}"
  body="${body//</\&lt;}"
  body="${body//>/\&gt;}"
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -u "$1" -h string:x-canonical-private-synchronous:screen-shader "$2" "$body"
  else
    printf '%s\n' "$3" >&2
  fi
}

# Without arguments it is the picker; with them it is screen-shader with a popup on top
if [[ $# -eq 0 ]]; then
  exec rofi -show "$MODE" -modi "$MODE:$MODI" -mesg "Full-screen effect"
fi

# stdout is passed through untouched, so "rofi-shader bright get" is still a number and
# "rofi-shader menu" is still a list; only stderr is turned into a popup
exec 3>&1
set +e
msg=$("$SS" "$@" 2>&1 1>&3 3>&-)
rc=$?
set -e
exec 3>&-

if [[ -n "$msg" ]]; then
  if ((rc)); then
    notify critical "Shader error (╯°□°）╯︵ ┻━┻" "$msg"
  else
    notify low "Shader" "$msg"
  fi
fi
exit "$rc"
