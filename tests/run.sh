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
skip() { printf '  skip %s (notifications are not observable here)\n' "$1"; }

state() { # $1 = stack, $2 = bright, $3 = slot
  printf 'stack=(%s)\nbright=%s\nslot=%s\n' "$1" "${2:-1.00}" "${3:-0}" >"$SCREEN_SHADER_STATE"
}
# The stack as a plain "a b c" — save_state pads with spaces, which is noise in a test
stack_now() { sed -n 's/^stack=(\(.*\))$/\1/p' "$SCREEN_SHADER_STATE" | tr -s ' ' | sed 's/^ *//; s/ *$//'; }
bright_now() { sed -n 's/^bright=//p' "$SCREEN_SHADER_STATE"; }
run() { # forget previous side effects, then run the manager
  : >"$CALLS"
  : >"$NOTIFY"
  "$SS" "$@"
}
emitted() { find "$XDG_RUNTIME_DIR/screen-shader" -name 'active-*.frag' | sort | tail -1; }
clean() { rm -f "$XDG_RUNTIME_DIR"/screen-shader/*.frag; }

# A wrapped manager pins libnotify ahead of PATH and notifies the real daemon, so the
# stub stays empty — find out once rather than asserting into the void
state ""
run effect clear >/dev/null 2>&1
notifies=0
[[ -s "$NOTIFY" ]] && notifies=1
notify_has() { if [[ "$notifies" == 1 ]]; then has "$@"; else skip "$1"; fi; }

# ── the picker's menu ────────────────────────────────────────────────────────────
section "menu"
state ""
menu="$(run menu)"
is "order comes from the // order: headers" \
  "none grayscale sepia invert warm cool vignette sharpen crt matrix posterize wave glitch jpeg" \
  "$(printf '%s\n' "$menu" | cut -d'|' -f2 | tr '\n' ' ' | sed 's/ $//')"
has "labels and emojis come from the headers" "$menu" "🌅 Warm (night)|warm"

state "crt grayscale"
menu="$(run menu)"
has "an active effect is marked with its apply number" "$menu" "01. 📺 CRT|crt"
has "the number follows stack order, not menu order" "$menu" "02. ⚫ Grayscale|grayscale"
hasnt "Normal is never marked" "$(run menu)" "01. 🌈"

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
notify_has "and it says so" "$(cat "$NOTIFY")" "Already in the stack"
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
notify_has "and names itself" "$out$(cat "$NOTIFY")" "nosuchthing"

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

printf '// label: Live\n// emoji: 🅰\n// order: 6\nvec3 effect(vec3 c, vec2 uv) { return texture(tex, uv + time).rgb; }\n' >"$custom/live.frag"
state "live"
SCREEN_SHADER_DIR="$custom" run restore
is "using time is what makes an effect animated — no table says so" \
  "hyprctl --batch keyword debug:damage_tracking 0 ; keyword debug:vfr 0" \
  "$(grep -F 'damage_tracking' "$CALLS")"
printf '// label: Warp\n// emoji: 🅱\n// order: 7\n// mentions time only in prose\nvec3 effect(vec3 c, vec2 uv) { return texture(tex, uv * 0.99).rgb; }\n' >"$custom/warp.frag"
state "warp"
SCREEN_SHADER_DIR="$custom" run restore
is "a comment saying time does not make it animated" \
  "hyprctl --batch keyword debug:damage_tracking 1 ; keyword debug:vfr 1" \
  "$(grep -F 'damage_tracking' "$CALLS")"

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
