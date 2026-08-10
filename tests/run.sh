#!/usr/bin/env bash

# Behaviour tests for screen-shader. Everything runs against a stub hyprctl in a
# scratch runtime/state directory, so a live session is never touched
#
#   tests/run.sh              run the suite
#   tests/run.sh --update     rewrite the golden shaders from the current output
#
# SCREEN_SHADER overrides which manager is exercised (default: the one next to tests/)

set -uo pipefail

here="$(dirname "$(readlink -f "${BASH_SOURCE[0]}")")"
SS="${SCREEN_SHADER:-$here/../screen-shader.sh}"
GOLDEN="$here/golden"
update=""
[[ "${1:-}" == "--update" ]] && update=1

WORK="$(mktemp -d)"
trap 'rm -rf "$WORK"' EXIT

# hyprctl is the only thing reaching outside; notify-send would otherwise pop real
# toasts on the developer's desktop while the suite runs
mkdir -p "$WORK/bin"
# /bin/sh, not env bash: the suite also runs inside a Nix sandbox, which has no /usr/bin
cat >"$WORK/bin/hyprctl" <<'EOF'
#!/bin/sh
printf 'hyprctl %s\n' "$*" >>"$CALLS"
EOF
cat >"$WORK/bin/notify-send" <<'EOF'
#!/bin/sh
printf 'notify %s\n' "$*" >>"$NOTIFY"
EOF
chmod +x "$WORK/bin/hyprctl" "$WORK/bin/notify-send"
export PATH="$WORK/bin:$PATH"
export XDG_RUNTIME_DIR="$WORK/rt"
export SCREEN_SHADER_STATE="$WORK/state"
# Never the developer's own added effects: the suite asserts the exact effect list
export SCREEN_SHADER_USER_DIR="$WORK/added"
export CALLS="$WORK/calls" NOTIFY="$WORK/notify"
mkdir -p "$XDG_RUNTIME_DIR"

pass=0
fail=0
ok() {
  pass=$((pass + 1))
  printf '  ok   %s\n' "$1"
}
bad() {
  fail=$((fail + 1))
  printf '  FAIL %s\n         want: %s\n         got:  %s\n' "$1" "$2" "$3"
}
is() { if [[ "$2" == "$3" ]]; then ok "$1"; else bad "$1" "$2" "$3"; fi; }
has() { if [[ "$2" == *"$3"* ]]; then ok "$1"; else bad "$1" "contains $3" "$2"; fi; }
hasnt() { if [[ "$2" != *"$3"* ]]; then ok "$1"; else bad "$1" "no $3" "$2"; fi; }

section() { printf '\n%s\n' "$1"; }

state() { # $1 = stack, $2 = bright, $3 = slot, $4 = suspended, $5 = suspended bright
  printf 'stack=(%s)\nbright=%s\nslot=%s\nsuspended=(%s)\nsuspended_bright=%s\n' \
    "$1" "${2:-1.00}" "${3:-0}" "${4:-}" "${5:-1.00}" >"$SCREEN_SHADER_STATE"
}
# A list as a plain "a b c" — save_state pads with spaces, which is noise in a test
list_now() { sed -n "s/^$1=(\(.*\))$/\1/p" "$SCREEN_SHADER_STATE" | tr -s ' ' | sed 's/^ *//; s/ *$//'; }
stack_now() { list_now stack; }
suspended_now() { list_now suspended; }
bright_now() { sed -n 's/^bright=//p' "$SCREEN_SHADER_STATE"; }
suspended_bright_now() { sed -n 's/^suspended_bright=//p' "$SCREEN_SHADER_STATE"; }
run() { # forget previous side effects, then run the manager
  : >"$CALLS"
  : >"$NOTIFY"
  "$SS" "$@"
}
# What the manager told the human. Its own stdout is machine output and stays out of it,
# which is the whole contract: rofi-shader turns exactly this into a popup
said() {
  # shellcheck disable=SC2069 # deliberate order: stderr takes over stdout, stdout goes away
  run "$@" 2>&1 >/dev/null
}
emitted() { find "$XDG_RUNTIME_DIR/screen-shader" -name 'active-*.frag' | sort | tail -1; }
clean() { rm -f "$XDG_RUNTIME_DIR"/screen-shader/*.frag; }

# ── the picker's menu ────────────────────────────────────────────────────────────
section "menu"
state ""
menu="$(run menu)"
is "order comes from the // order: headers" \
  "none grayscale sepia invert warm reading cool vignette sharpen crt matrix posterize wave glitch jpeg" \
  "$(printf '%s\n' "$menu" | cut -d'|' -f2 | tr '\n' ' ' | sed 's/ $//')"
has "labels and emojis come from the headers" "$menu" "🌅 Warm (night)|warm"

state "crt grayscale"
menu="$(run menu)"
has "an active effect is marked with its apply number" "$menu" "01. 📺 CRT|crt"
has "the number follows stack order, not menu order" "$menu" "02. ⚫ Grayscale|grayscale"
hasnt "Normal is never marked" "$(run menu)" "01. 🌈"

# ── the rofi picker ──────────────────────────────────────────────────────────────
section "picker"
# NUL and the 0x1f separator are turned into @ and | so the assertions stay readable
# The whole chain the picker really goes through: modi -> UI layer -> manager
picker_out() {
  ROFI_RETV=0 SCREEN_SHADER="$SS" SCREEN_SHADER_UI="$here/../rofi-shader.sh" \
    bash "$here/../shader-modi.sh" | tr '\000\037' '@|'
}
state ""
out="$(picker_out)"
has "the mode name is set through the script protocol" "$out" "@prompt|📺"
has "the selection is kept, so effects can be clicked in a row" "$out" "@keep-selection|true"
has "the current brightness rides in the message" "$out" "brightness 100%"
has "an effect carries its name in a hidden info field" "$out" "Grayscale@info|grayscale"
has "the brightness buttons follow Normal" "$out" "@info|__bright_up__"
out="$(ROFI_SHADER_PROMPT=X picker_out)"
has "and the mode name is overridable" "$out" "@prompt|X"

# ── the waybar indicator ─────────────────────────────────────────────────────────
section "status"
state "" "1.00"
is "idle module is empty so waybar hides it" '{"text":"","tooltip":"","class":"off"}' "$(run status)"
state "" "0.50"
has "brightness alone still shows" "$(run status)" '"text":"🔅 50%"'
state "sepia" "1.00"
has "one effect shows its emoji" "$(run status)" '"text":"🟤"'
has "class is the effect name" "$(run status)" '"class":"sepia"'
state "sepia invert" "0.75"
has "a stack concatenates emojis" "$(run status)" '"text":"🟤🔄 75%"'
has "tooltip joins the labels in order" "$(run status)" '"tooltip":"Sepia + Invert · brightness 75%"'
has "class is stack for more than one" "$(run status)" '"class":"stack"'

# ── the effect stack ─────────────────────────────────────────────────────────────
section "effect"
state ""
run effect push sepia >/dev/null
is "push appends to durable state" "sepia" "$(stack_now)"
run effect push invert >/dev/null
is "a second push stacks rather than replaces" "sepia invert" "$(stack_now)"
run effect push sepia >/dev/null
is "pushing a member again is a no-op" "sepia invert" "$(stack_now)"
has "and it says so" "$(said effect push sepia)" "Already in the stack"
run effect toggle sepia >/dev/null
is "toggle removes a member" "invert" "$(stack_now)"
run effect toggle crt >/dev/null
is "toggle adds a non-member" "invert crt" "$(stack_now)"
run effect set warm >/dev/null
is "set replaces the whole stack" "warm" "$(stack_now)"
run effect clear >/dev/null
is "clear empties it" "" "$(stack_now)"

state "sepia"
run effect push none >/dev/null
is "pushing Normal clears instead of stacking a passthrough" "" "$(stack_now)"

state "jpeg"
run effect next >/dev/null
is "next wraps past the last effect back to Normal" "" "$(stack_now)"
state ""
run effect prev >/dev/null
is "prev from Normal wraps to the last effect" "jpeg" "$(stack_now)"

out="$(run effect push nosuchthing 2>&1)"
is "an unknown effect fails loudly" 1 "$?"
has "and names itself" "$out" "nosuchthing"

# ── soft brightness ──────────────────────────────────────────────────────────────
section "bright"
state "" "1.00"
run bright up >/dev/null
is "up steps by 0.05" "1.05" "$(bright_now)"
run bright down >/dev/null
is "down steps back" "1.00" "$(bright_now)"
state "" "1.98"
run bright up >/dev/null
is "up clamps at 2.00" "2.00" "$(bright_now)"
state "" "0.12"
run bright down >/dev/null
is "down clamps at 0.10" "0.10" "$(bright_now)"
run bright set 9 >/dev/null
is "set clamps high" "2.00" "$(bright_now)"
run bright set 0 >/dev/null
is "set clamps low" "0.10" "$(bright_now)"
run bright reset >/dev/null
is "reset is exactly 1.00" "1.00" "$(bright_now)"
run bright toggle >/dev/null
is "toggle halves" "0.50" "$(bright_now)"
run bright toggle >/dev/null
is "toggle restores" "1.00" "$(bright_now)"
is "get reports whole percent" "100" "$(run bright get)"
state "" "0.85"
is "get rounds down to the percent" "85" "$(run bright get)"

state "" "1.00"
run reset-all >/dev/null
is "reset-all drops effects" "" "$(stack_now)"
is "reset-all drops brightness" "1.00" "$(bright_now)"

# ── what actually reaches the compositor ─────────────────────────────────────────
section "compositor"
state "" "1.00"
run restore
has "nothing on means the slot is emptied" "$(cat "$CALLS")" "screen_shader [[EMPTY]]"
state "" "0.50"
run restore
has "dimming alone still needs a shader" "$(cat "$CALLS")" "screen_shader $XDG_RUNTIME_DIR/screen-shader/active-"

state "grayscale"
run restore
is "a per-pixel effect keeps partial damage" \
  "hyprctl --batch keyword debug:damage_tracking 2 ; keyword debug:vfr 1" \
  "$(grep -F 'damage_tracking' "$CALLS")"
state "crt"
run restore
is "offset sampling needs whole-monitor damage" \
  "hyprctl --batch keyword debug:damage_tracking 1 ; keyword debug:vfr 1" \
  "$(grep -F 'damage_tracking' "$CALLS")"
state "wave"
run restore
is "animation needs every frame and no VFR" \
  "hyprctl --batch keyword debug:damage_tracking 0 ; keyword debug:vfr 0" \
  "$(grep -F 'damage_tracking' "$CALLS")"
state "grayscale wave"
run restore
is "the most demanding effect in the stack decides" \
  "hyprctl --batch keyword debug:damage_tracking 0 ; keyword debug:vfr 0" \
  "$(grep -F 'damage_tracking' "$CALLS")"

state "sepia" "0.90" 0
run restore
first="$(grep -o 'active-[01]' "$CALLS")"
run restore
second="$(grep -o 'active-[01]' "$CALLS")"
if [[ "$first" != "$second" ]]; then
  ok "the shader path alternates so Hyprland re-reads it"
else
  bad "the shader path alternates so Hyprland re-reads it" "two different paths" "$first twice"
fi

# ── shader composition ───────────────────────────────────────────────────────────
section "composition"
clean
state "sepia crt" "1.00"
run restore
body="$(cat "$(emitted)")"
sepia_at=$(printf '%s\n' "$body" | grep -n 'vintage' | cut -d: -f1 | tail -1)
crt_at=$(printf '%s\n' "$body" | grep -n 'Retro CRT' | cut -d: -f1 | tail -1)
if [[ "$crt_at" -lt "$sepia_at" ]]; then
  ok "geometry runs before colour whatever the stack order"
else
  bad "geometry runs before colour whatever the stack order" "crt before sepia" "crt@$crt_at sepia@$sepia_at"
fi
has "the chain applies the second body to the first" "$body" "c = effect_1(c, v_texcoord);"
has "brightness is a compile-time constant" "$body" "#define BRIGHTNESS 1.00"
hasnt "metadata headers stay out of the GLSL" "$body" "// label:"

clean
state "crt glitch" "1.00"
run restore
body="$(cat "$(emitted)")"
is "the second body gets its definitions suffixed" 1 "$(grep -c 'float hash_1(' <<<"$body")"

# ── flash ────────────────────────────────────────────────────────────────────────
section "flash"
clean
state "crt sepia" "1.00"
run flash glitch 0.1
flash="$(cat "$XDG_RUNTIME_DIR/screen-shader/flash.frag")"
has "the flash body leads the chain" "$flash" "Animated glitch"
has "colour effects still compose over it" "$flash" "vintage"
hasnt "a geometric member is dropped — one slot, one pass" "$flash" "Retro CRT"
is "durable state survives the flash" "crt sepia" "$(stack_now)"

state "sepia" "1.00"
run flash -k glitch 0.1
is "-k is a no-op while the stack is busy" 0 "$?"
is "and leaves the state alone" "sepia" "$(stack_now)"

# ── effects are discovered, not listed ───────────────────────────────────────────
section "discovery"
custom="$WORK/shaders"
mkdir -p "$custom"
cp "$here/../shaders/none.frag" "$custom/"
printf '// label: Zero\n// emoji: 🅾\n// order: 5\nvec3 effect(vec3 c, vec2 uv) { return c * 0.5; }\n' >"$custom/zero.frag"
printf 'vec3 effect(vec3 c, vec2 uv) { return c; }\n' >"$custom/bare.frag"
menu="$(SCREEN_SHADER_DIR="$custom" run menu)"
is "a dropped-in .frag needs no registration" \
  "none zero bare" \
  "$(printf '%s\n' "$menu" | cut -d'|' -f2 | tr '\n' ' ' | sed 's/ $//')"
has "its header drives the picker entry" "$menu" "🅾 Zero|zero"
has "a header-less effect falls back to its file name" "$menu" "🎬 bare|bare"

# ── the render class comes from the header ──────────────────────────────────────
section "render class"
# One shader alone in a scratch directory; its class is the damage_tracking it asks for
mode_of() { # $1 = the whole .frag
  local dir="$WORK/one"
  rm -rf "$dir"
  mkdir -p "$dir"
  printf '%s\n' "$1" >"$dir/probe.frag"
  state "probe"
  SCREEN_SHADER_DIR="$dir" run restore >/dev/null
  case "$(grep -F 'damage_tracking' "$CALLS")" in
    *"damage_tracking 0"*) printf 'animated' ;;
    *"damage_tracking 1"*) printf 'fullstatic' ;;
    *) printf 'default' ;;
  esac
}

is "a header-less effect costs the least" "default" \
  "$(mode_of 'vec3 effect(vec3 c, vec2 uv) { return c * 0.5; }')"
is "// animated: yes needs no time in the code" "animated" "$(mode_of '// animated: yes
vec3 effect(vec3 c, vec2 uv) { return c * 0.5; }')"
is "// samples: yes asks for whole-monitor damage" "fullstatic" "$(mode_of '// samples: yes
vec3 effect(vec3 c, vec2 uv) { return c * 0.5; }')"
is "animation outranks sampling" "animated" "$(mode_of '// animated: yes
// samples: yes
vec3 effect(vec3 c, vec2 uv) { return texture(tex, uv).rgb; }')"
is "true is yes as well, whatever the case" "animated" "$(mode_of '// animated: TRUE
vec3 effect(vec3 c, vec2 uv) { return c; }')"
is "anything else is a no" "default" "$(mode_of '// animated: maybe
vec3 effect(vec3 c, vec2 uv) { return c; }')"
is "the header alone decides the class" "default" "$(mode_of '// label: Live
vec3 effect(vec3 c, vec2 uv) { return texture(tex, uv + time).rgb; }')"

# ── adding and removing effects at runtime ──────────────────────────────────────
section "add"
src="$WORK/src"
mkdir -p "$src"
printf 'vec3 effect(vec3 c, vec2 uv) { return c * 0.5; }\n' >"$src/half.frag"
printf '#version 300 es\nprecision highp float;\nin vec2 v_texcoord;\nuniform sampler2D tex;\nout vec4 fragColor;\nvoid main() { fragColor = texture(tex, v_texcoord); }\n' >"$src/standalone.frag"

state ""
run add "$src/half.frag" --label Half --emoji 🅷 --order 7 >/dev/null
is "the added file lands in the writable directory" 0 "$([[ -f "$SCREEN_SHADER_USER_DIR/half.frag" ]] && echo 0 || echo 1)"
has "and shows up in the menu with the flags as its header" "$(run menu)" "🅷 Half|half"
is "the flags are written on top of the file" \
  "// label: Half|// emoji: 🅷|// order: 7" \
  "$(head -3 "$SCREEN_SHADER_USER_DIR/half.frag" | tr '\n' '|' | sed 's/|$//')"

out="$(run add "$src/half.frag" --label Other 2>&1)"
is "adding the same name twice needs -f" 1 "$?"
has "and says why" "$out" "Already added"
run add "$src/half.frag" --label Other -f >/dev/null
has "-f replaces it" "$(run menu)" "🎬 Other|half"

out="$(run add "$src/standalone.frag" 2>&1)"
is "a standalone shader is not taken for one of ours" 1 "$?"
has "and the message names the way out" "$out" "--raw"
out="$(run add "$src/half.frag" --name rawish --raw 2>&1)"
is "and --raw on a file without main() is refused too" 1 "$?"

run add "$src/standalone.frag" --raw --label Plain --emoji 🅿 --order 8 >/dev/null
has "a raw shader adds fine when declared" "$(run menu)" "🅿 Plain|standalone"
state "standalone"
run restore
body="$(cat "$(emitted)")"
has "and reaches the compositor as it was written" "$body" "void main()"
hasnt "with no generated preamble around it" "$body" "#define BRIGHTNESS"
hasnt "and its header stripped" "$body" "// label:"

# ── a raw shader owns the frame while it is on ──────────────────────────────────
section "raw"
state "crt sepia" "0.85"
run effect toggle standalone >/dev/null
is "a raw effect takes the slot alone" "standalone" "$(stack_now)"
is "and the composition is put aside, not dropped" "crt sepia" "$(suspended_now)"
is "brightness goes with it, because there is nothing to multiply" "1.00" "$(bright_now)"
is "and waits with the stack" "0.85" "$(suspended_bright_now)"
has "the menu marks it as raw rather than with a place in an order" "$(run menu)" "raw. 🅿 Plain|standalone"
has "and shows what is waiting, in brackets" "$(run menu)" "(01.) 📺 CRT|crt"
has "the indicator says the stack is suspended" "$(run status)" "stack suspended"

out="$(said bright down)"
is "brightness under a raw effect is refused, not recorded" "1.00" "$(bright_now)"
has "and says why" "$out" "owns the frame"
is "reading it still works, so the UI can ask" "100" "$(run bright get)"

run effect toggle standalone >/dev/null
is "toggling it off gives the composition back" "crt sepia" "$(stack_now)"
is "with the brightness it was holding" "0.85" "$(bright_now)"
is "and nothing is left waiting" "" "$(suspended_now)"

state "crt sepia" "0.85"
run effect toggle standalone >/dev/null
run effect toggle warm >/dev/null
is "picking another effect ends the raw effect's turn" "crt sepia warm" "$(stack_now)"
is "and brings the brightness back too" "0.85" "$(bright_now)"

state "crt sepia" "0.85"
run effect toggle standalone >/dev/null
run effect toggle crt >/dev/null
is "picking a suspended one just brings the stack back" "crt sepia" "$(stack_now)"

state "crt" "0.85"
run effect toggle standalone >/dev/null
run effect set warm >/dev/null
is "set replaces the stack outright" "warm" "$(stack_now)"
is "but the suspended brightness still comes back" "0.85" "$(bright_now)"

state "crt" "0.85"
run effect toggle standalone >/dev/null
run effect clear >/dev/null
is "clear means clear — nothing waits any more" "" "$(suspended_now)"
is "and only the brightness survives it" "0.85" "$(bright_now)"

state "crt" "0.85"
run effect toggle standalone >/dev/null
run reset-all >/dev/null
is "reset-all drops the suspended stack as well" "" "$(suspended_now)"
is "and its brightness with it" "1.00" "$(bright_now)"

# A state file can carry a stack no command would build: an older version wrote it, or
# an effect turned raw under it (add -f --raw, extraShaders)
clean
state "standalone sepia" "0.90"
run restore
is "a raw effect found beside others still takes the slot" "standalone" "$(stack_now)"
is "and the others are what waits" "sepia" "$(suspended_now)"
body="$(cat "$(emitted)")"
hasnt "so nothing composes over it" "$body" "vintage"

clean
state "standalone standalone2" "1.00"
cp "$SCREEN_SHADER_USER_DIR/standalone.frag" "$SCREEN_SHADER_USER_DIR/standalone2.frag"
run restore
is "two raw effects cannot share it either" "standalone" "$(stack_now)"
has "and the shader is a real one, not a body-less main()" "$(cat "$(emitted)")" "void main()"
rm -f "$SCREEN_SHADER_USER_DIR/standalone2.frag"

# raw says nothing about how the frame is redrawn — that is still animated/samples
is "a raw effect still declares its render class" "fullstatic" "$(mode_of '// raw: yes
// samples: yes
#version 300 es
precision highp float;
in vec2 v_texcoord;
uniform sampler2D tex;
out vec4 fragColor;
void main() { fragColor = texture(tex, v_texcoord); }')"

run add "$src/standalone.frag" --name flagged --raw --samples --label Flagged >/dev/null
is "add writes every flag it was given, raw beside the rest" \
  "// label: Flagged|// samples: yes|// raw: yes" \
  "$(head -3 "$SCREEN_SHADER_USER_DIR/flagged.frag" | tr '\n' '|' | sed 's/|$//')"
run add "$src/half.frag" --name unflagged --no-raw --label Unflagged >/dev/null
has "and --no-raw is written just as plainly" "$(head -2 "$SCREEN_SHADER_USER_DIR/unflagged.frag")" "// raw: no"
run remove flagged >/dev/null
run remove unflagged >/dev/null

# ── remove ──────────────────────────────────────────────────────────────────────
section "remove"
state "half"
run remove half >/dev/null
is "removing takes the file away" 1 "$([[ -f "$SCREEN_SHADER_USER_DIR/half.frag" ]] && echo 0 || echo 1)"
is "and the effect leaves the stack with it" "" "$(stack_now)"
out="$(run remove sepia 2>&1)"
is "an installed effect is not ours to delete" 1 "$?"
has "and it says so" "$out" "comes with the package"

run add "$src/half.frag" --name sepia --label Mine >/dev/null
has "an added name shadows the installed effect" "$(run menu)" "🎬 Mine|sepia"
run remove sepia >/dev/null
has "and removing it uncovers the installed one again" "$(run menu)" "🟤 Sepia|sepia"
run remove standalone >/dev/null

# ── golden shaders ───────────────────────────────────────────────────────────────
section "golden"
mkdir -p "$GOLDEN"
for case in "grayscale" "crt" "wave" "crt grayscale sepia" "glitch crt vignette" \
  "jpeg sharpen" "matrix warm" "none"; do
  name="${case// /+}"
  clean
  state "$case" "0.80"
  run restore
  got="$(emitted)"
  if [[ -n "$update" ]]; then
    cp "$got" "$GOLDEN/$name.frag"
    printf '  updated %s\n' "$name.frag"
  elif diff -q "$GOLDEN/$name.frag" "$got" >/dev/null 2>&1; then
    ok "generated GLSL for [$case] is unchanged"
  else
    bad "generated GLSL for [$case] is unchanged" "tests/golden/$name.frag" "$(diff -u "$GOLDEN/$name.frag" "$got" | head -15)"
  fi
done

printf '\n%s passed, %s failed\n' "$pass" "$fail"
[[ $fail -eq 0 ]]
