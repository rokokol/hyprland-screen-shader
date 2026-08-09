#!/usr/bin/env bash

set -euo pipefail

usage() {
  cat <<'EOF'
screen-shader — Hyprland full-screen effects and software brightness

Commands:
  effect push <name>      ADD an effect to the stack (composited over the current ones)
  effect set <name>       REPLACE the stack with a single effect
  effect clear            clear the stack (turn all effects off)
  effect toggle <name>    in the stack — remove it; not — add it
  effect next|prev        replace the stack with the next/previous effect
  bright up|down          soft brightness ±5% (clamp 10..200%)
  bright reset            brightness 100%
  bright toggle           100% ↔ 50%
  bright set <0.10..2>    brightness exactly
  bright get              current brightness in percent (integer, for the UI)
  add <file.frag> [flags] install an effect into the writable directory
                          --name <n>       effect name (default: the file name)
                          --label/--emoji/--order <v>
                          --animated  --samples  --raw   (--no-… for the opposite)
                          -f               replace one added earlier
                          the flags are written as header lines on top of the file
  remove <name>           drop an added effect (an installed one is not ours to delete)
  flash [-k] <name> [sec] effect for N seconds (default 1.0), then revert;
                          composited OVER the current stack (composition);
                          durable state is not touched;
                          -k — no-op if the stack is non-empty
  restore                 re-read state and apply again
                          (exec on every Hyprland reload — the slot is runtime)
  reset-all               drop effects and brightness in one apply
  status                  JSON for a waybar custom module
  menu                    "<emoji> <label>|<name>" lines for the rofi picker
                          (active ones marked with an apply number: 01. 02. 03.)
  help                    this help

Effects STACK: every `effect push` adds a filter over the previous ones (the rofi
picker sends `effect toggle`), and they compose into one shader until the stack is
cleared (`effect clear`, or the "Normal" item in the picker). Hyprland has one shader
slot (decoration:screen_shader), so all effects in the stack plus brightness are
assembled into one generated GLSL. Effects that sample the texture with an offset
(crt/wave/glitch) go first in the chain (geometry), colour filters after; multiple
geometric ones don't stack (the last overrides the previous ones) — a limitation of
the single slot

One effect is one file, <name>.frag, holding the function vec3 effect(vec3 c, vec2 uv)
under a header of "// label:", "// emoji:", "// order:". Effects are read from TWO
directories: the installed one ($SCREEN_SHADER_DIR, read-only under Nix) and the
writable one ($SCREEN_SHADER_USER_DIR) that "add" writes to; a name present in both is
taken from the writable one

Three more header keys, all "no" unless declared:
"// animated: yes" — the picture changes over time (the body uses time), so a frame every tick
"// samples: yes"  — a pixel takes its colour from elsewhere on screen (the body reads tex
                     away from uv), so damage has to cover the whole monitor; such effects
                     also lead the chain, ahead of the colour filters
"// raw: yes"      — a standalone shader with its own #version and main(), handed to
                     Hyprland as it is. It owns the frame, so it runs alone: no stacking
                     with other effects and no soft brightness over it

Environment:
  SCREEN_SHADER_DIR    the installed effects (default: shaders/ next to this script)
  SCREEN_SHADER_USER_DIR  the added ones (default: $XDG_DATA_HOME/screen-shader/shaders)
  SCREEN_SHADER_STATE  durable state file (default: $XDG_STATE_HOME/screen-shader/state)
  WAYBAR_SHADER_SIGNAL RT signal to poke waybar with after a change (unset = don't)
  SHADER_NO_SIGNAL     set to any value to suppress that signal
EOF
}

notify_error() {
  if command -v notify-send >/dev/null 2>&1; then
    notify-send -u critical "Shader error (╯°□°）╯︵ ┻━┻" "$1" && return
  fi
  printf '%s\n' "$1" >&2
}

notify_info() {
  command -v notify-send >/dev/null 2>&1 && notify-send -u low "$1" "$2" || true
}

# SHADER_NO_SIGNAL suppresses the signal on restore at session start: the default
# action of an RT signal is to kill the process, and waybar may not have installed
# a handler yet
signal_waybar() {
  [[ -z "${SHADER_NO_SIGNAL:-}" ]] || return 0
  [[ -n "${WAYBAR_SHADER_SIGNAL:-}" ]] || return 0
  pkill -RTMIN+"$WAYBAR_SHADER_SIGNAL" waybar 2>/dev/null || true
}

# The keys an effect header may declare — the one list the scanner, the header stripper
# and "add" all read
HEADER_KEYS='label|emoji|order|animated|samples|raw'

# Resolve through symlinks, so a link to this script on PATH still finds its shaders
SELF="$(readlink -f "${BASH_SOURCE[0]}")"
SHADER_DIR="${SCREEN_SHADER_DIR:-$(dirname "$SELF")/shaders}"
# Effects added with "add" live apart from the installed ones: that directory has to be
# writable, and under Nix the installed one is a read-only store path. Scanned second,
# so a name landing here replaces the installed effect of the same name
USER_DIR="${SCREEN_SHADER_USER_DIR:-${XDG_DATA_HOME:-$HOME/.local/share}/screen-shader/shaders}"
RUNTIME_DIR="${XDG_RUNTIME_DIR:-/tmp}/screen-shader"
STATE="${SCREEN_SHADER_STATE:-${XDG_STATE_HOME:-$HOME/.local/state}/screen-shader/state}"

# Filled by load_effects from the .frag files themselves — there is no table here
EFFECTS=()
declare -A EMOJI LABEL ANIMATED SAMPLES RAW FILE

# One awk pass over the "// key: value" header of every .frag — it carries the whole
# effect record: label, emoji and menu position, plus the two facts Hyprland needs
# (does it move, does it reach outside its own pixel). Both render keys default to no,
# the plain colour filter that most effects are
load_effects() {
  local name emoji label anim samp raw file f
  # One file per effect name, the user directory winning — the same rule extraShaders
  # follows at build time
  local -A found=()
  for f in "$SHADER_DIR"/*.frag "$USER_DIR"/*.frag; do
    [[ -f "$f" ]] || continue
    name="${f##*/}"
    found["${name%.frag}"]="$f"
  done
  if [[ ${#found[@]} -eq 0 ]]; then
    notify_error "No .frag files in $SHADER_DIR"
    exit 1
  fi
  while IFS='|' read -r name emoji label anim samp raw file; do
    EFFECTS+=("$name")
    EMOJI[$name]="$emoji"
    LABEL[$name]="$label"
    ANIMATED[$name]="$anim"
    SAMPLES[$name]="$samp"
    RAW[$name]="$raw"
    FILE[$name]="$file"
  done < <(
    awk -v keys="$HEADER_KEYS" '
      function yes(v) {
        v = tolower(v)
        return (v == "yes" || v == "true" || v == "on" || v == "1") ? 1 : 0
      }
      function flush() {
        if (name != "") printf "%03d|%s|%s|%s|%s|%s|%s|%s\n", order, name, emoji, label, anim, samp, raw, file
      }
      FNR == 1 {
        flush()
        file = FILENAME
        name = FILENAME; sub(/.*\//, "", name); sub(/\.frag$/, "", name)
        order = 500; emoji = "🎬"; label = name; anim = 0; samp = 0; raw = 0
      }
      $0 ~ "^[ \t]*//[ \t]*(" keys ")[ \t]*:" {
        key = $0; sub(/^[ \t]*\/\/[ \t]*/, "", key); sub(/[ \t]*:.*/, "", key)
        val = $0; sub(/^[^:]*:[ \t]*/, "", val); sub(/[ \t]+$/, "", val)
        if (key == "label") label = val
        else if (key == "emoji") emoji = val
        else if (key == "order") order = val + 0
        else if (key == "animated") anim = yes(val)
        else if (key == "samples") samp = yes(val)
        else raw = yes(val)
      }
      END { flush() }
    ' "${found[@]}" | sort | cut -d'|' -f2-
  )
}

# Stack of active effects (in the order they were added). Empty = nothing applied
stack=()
bright="1.00"
# Hyprland does NOT recompile the shader if given the same path. So we write to
# alternating files (active-0/active-1) — the path always changes and the shader is
# guaranteed to be re-read (otherwise a brightness change with an active stack isn't
# applied)
slot=0

load_state() {
  stack=()
  if [[ -f "$STATE" ]]; then
    # shellcheck disable=SC1090
    source "$STATE"
  fi
}

save_state() {
  mkdir -p "$(dirname "$STATE")"
  {
    printf 'stack=('
    printf '%s ' "${stack[@]}"
    printf ')\n'
    printf 'bright=%s\n' "$bright"
    printf 'slot=%s\n' "$slot"
  } >"$STATE"
}

# Index of an effect in EFFECTS (or -1)
effect_index() {
  local i
  for i in "${!EFFECTS[@]}"; do
    [[ "${EFFECTS[$i]}" == "$1" ]] && {
      printf '%s' "$i"
      return
    }
  done
  printf '%s' -1
}

in_list() {
  local item="$1"
  shift
  local x
  for x in "$@"; do
    [[ "$item" == "$x" ]] && return 0
  done
  return 1
}

# 1-based position of an effect in the stack (apply order) — prints the number and
# returns 0 if the effect is in the stack; otherwise returns 1 and prints nothing
stack_position() {
  local i=1 x
  for x in "${stack[@]}"; do
    [[ "$x" == "$1" ]] && {
      printf '%s' "$i"
      return 0
    }
    i=$((i + 1))
  done
  return 1
}

# The effect declared "// samples: yes" (geometry/distortion) — it goes first in the chain
samples_texture() {
  [[ "${SAMPLES[$1]:-0}" == 1 ]]
}

# A standalone shader ("// raw: yes"): it brings its own main(), so it takes the slot
# whole — nothing composes with it and soft brightness cannot multiply its output
is_raw() {
  [[ "${RAW[$1]:-0}" == 1 ]]
}

# Render mode by the effect list: take the most demanding one
#   animated   — one of them declared animation: damage 0 (draw every frame) + VFR off
#                (with VFR on Hyprland goes idle and the animation stutters);
#   fullstatic — there's a static one with offset sampling (curvature): damage 1 — on
#                any change redraw the whole monitor (otherwise precise damage breaks
#                the distorted sampling), but sleep when idle; VFR on;
#   default    — only per-pixel effects: default damage 2 + VFR (partial ok)
set_render_mode() {
  case "$1" in
    animated) hyprctl --batch "keyword debug:damage_tracking 0 ; keyword debug:vfr 0" >/dev/null ;;
    fullstatic) hyprctl --batch "keyword debug:damage_tracking 1 ; keyword debug:vfr 1" >/dev/null ;;
    *) hyprctl --batch "keyword debug:damage_tracking 2 ; keyword debug:vfr 1" >/dev/null ;;
  esac
}

render_mode_for() { # $@ = effect names
  local n
  for n in "$@"; do [[ "${ANIMATED[$n]:-0}" == 1 ]] && {
    printf 'animated'
    return
  }; done
  for n in "$@"; do samples_texture "$n" && {
    printf 'fullstatic'
    return
  }; done
  printf 'default'
}

# The GLSL of an effect without its metadata header — that header is for the manager,
# not for the compiler
frag_body() { # $1 = file
  sed -E "/^[[:space:]]*\/\/[[:space:]]*($HEADER_KEYS)[[:space:]]*:/d" "$1"
}

# Rename all top-level definitions of an effect body (effect, hash, …) with the
# suffix $2 — for composing several bodies in one shader without conflicts
rename_defs() { # $1 = file, $2 = suffix
  local names n args=()
  names=$(grep -oE '^(const )?(float|int|bool|vec[234]|mat[234]) +[A-Za-z_][A-Za-z0-9_]*' "$1" | awk '{ print $NF }')
  for n in $names; do
    args+=(-e "s/\b$n\b/${n}$2/g")
  done
  if [[ ${#args[@]} -eq 0 ]]; then
    frag_body "$1"
  else
    frag_body "$1" | sed "${args[@]}"
  fi
}

# Assemble the full GLSL from a chain of effect bodies: $1 = output file, then a
# list of .frag files. The first body is used as is (function effect), the rest are
# renamed (effect_1, effect_2, …) and applied in turn to the result of the previous
# one. time is seconds since start; an effect that ignores it has the uniform
# optimized out by the compiler, so the preamble can declare it unconditionally
emit_shader() {
  local out="$1"
  shift
  local bodies=("$@") b i=0
  # Atomic write: write to a temp file, then mv — Hyprland won't see a half-written
  # shader on concurrent calls
  local tmp="${out}.tmp.$$"
  {
    printf '#version 300 es\n'
    printf 'precision highp float;\n\n'
    printf 'in vec2 v_texcoord;\n'
    printf 'uniform sampler2D tex;\n'
    printf 'uniform float time;\n'
    printf 'out vec4 fragColor;\n\n'
    printf '#define BRIGHTNESS %s\n\n' "$bright"
    for b in "${bodies[@]}"; do
      if [[ $i -eq 0 ]]; then
        frag_body "$b"
      else
        printf '\n'
        rename_defs "$b" "_$i"
      fi
      i=$((i + 1))
    done
    printf '\nvoid main() {\n'
    printf '    vec4 src = texture(tex, v_texcoord);\n'
    printf '    vec3 c = effect(src.rgb, v_texcoord);\n'
    i=1
    while [[ $i -lt ${#bodies[@]} ]]; do
      printf '    c = effect_%s(c, v_texcoord);\n' "$i"
      i=$((i + 1))
    done
    printf '    c *= BRIGHTNESS;\n'
    printf '    fragColor = vec4(c, src.a);\n'
    printf '}\n'
  } >"$tmp"
  mv -f "$tmp" "$out"
}

# Order the stack for the chain: geometric ones (sample the texture) first, color
# ones after. Prints one name per line
ordered_stack() {
  local e
  # A raw effect never joins a chain — it owns the slot alone or it is skipped
  for e in "${stack[@]}"; do
    is_raw "$e" && continue
    samples_texture "$e" && printf '%s\n' "$e"
  done
  for e in "${stack[@]}"; do
    is_raw "$e" && continue
    samples_texture "$e" || printf '%s\n' "$e"
  done
  return 0
}

# Pick the slot file to write next into ACTIVE. Alternating, so the path Hyprland is
# handed always differs and it re-reads the shader instead of keeping the compiled one.
# A global rather than a printed value: the slot number has to survive into save_state
ACTIVE=""
next_slot() {
  slot=$((1 - slot))
  ACTIVE="$RUNTIME_DIR/active-$slot.frag"
}

apply() { # $1 (opt.) = transient: don't save state to durable state
  # Fully remove the shader if there are neither effects nor dimming
  if [[ ${#stack[@]} -eq 0 && "$bright" == "1.00" ]]; then
    set_render_mode default
    hyprctl keyword decoration:screen_shader "[[EMPTY]]" >/dev/null
    [[ "${1:-}" == "transient" ]] || save_state
    signal_waybar
    return
  fi

  # A raw effect goes to the slot as it was written, header lines aside: it owns main(),
  # so there is nothing to compose it with and no place to multiply brightness in
  if [[ ${#stack[@]} -eq 1 ]] && is_raw "${stack[0]}"; then
    local tmp
    next_slot
    tmp="$ACTIVE.tmp.$$"
    frag_body "${FILE[${stack[0]}]}" >"$tmp"
    mv -f "$tmp" "$ACTIVE"
    set_render_mode "$(render_mode_for "${stack[0]}")"
    hyprctl keyword decoration:screen_shader "$ACTIVE" >/dev/null
    [[ "${1:-}" == "transient" ]] || save_state
    signal_waybar
    return
  fi

  # Body list in chain order. An empty stack with bright<1 is a single passthrough
  local bodies=() e
  if [[ ${#stack[@]} -eq 0 ]]; then
    bodies=("${FILE[none]:?the none passthrough is missing from the shader directory}")
  else
    while IFS= read -r e; do
      [[ -n "${FILE[$e]:-}" ]] || {
        notify_error "Shader not found: $e"
        exit 1
      }
      bodies+=("${FILE[$e]}")
    done < <(ordered_stack)
  fi

  next_slot
  emit_shader "$ACTIVE" "${bodies[@]}"

  set_render_mode "$(render_mode_for "${stack[@]}")"
  hyprctl keyword decoration:screen_shader "$ACTIVE" >/dev/null
  [[ "${1:-}" == "transient" ]] || save_state
  signal_waybar
}

# Check the name and that the file exists
require_effect() {
  if [[ -z "${FILE[$1]:-}" ]]; then
    notify_error "Unknown effect: $1"
    exit 1
  fi
}

# A raw effect cannot share the slot, so adding one drops whatever was there — and so
# does adding anything else while one is active. Emptying the stack beats refusing:
# the picker toggles effects, and a refusal there just looks like a dead entry
make_room_for() { # $1 = the effect about to be added
  if is_raw "$1"; then
    [[ ${#stack[@]} -eq 0 ]] || notify_info "Shader" "${LABEL[$1]} is a raw shader — it runs alone (・_・)"
    stack=()
  elif [[ ${#stack[@]} -eq 1 ]] && is_raw "${stack[0]}"; then
    notify_info "Shader" "${LABEL[${stack[0]}]} is a raw shader — dropping it (・_・)"
    stack=()
  fi
}

push_effect() {
  local name="$1"
  # "Normal" = reset the whole stack
  if [[ "$name" == "none" ]]; then
    clear_stack
    return
  fi
  require_effect "$name"
  make_room_for "$name"
  if in_list "$name" "${stack[@]}"; then
    notify_info "Shader" "Already in the stack: ${LABEL[$name]} (・_・)"
    return
  fi
  stack+=("$name")
  apply
  notify_info "Shader" "Added: ${LABEL[$name]} · in the stack ${#stack[@]} （-＾〇＾-）"
}

set_single() {
  local name="$1"
  if [[ "$name" == "none" ]]; then
    clear_stack
    return
  fi
  require_effect "$name"
  stack=("$name")
  apply
  notify_info "Shader" "Effect: ${LABEL[$name]} （-＾〇＾-）"
}

toggle_effect() {
  local name="$1" e new=()
  # "Normal" = reset the whole stack, not adding none to the chain
  if [[ "$name" == "none" ]]; then
    clear_stack
    return
  fi
  require_effect "$name"
  if in_list "$name" "${stack[@]}"; then
    for e in "${stack[@]}"; do [[ "$e" == "$name" ]] || new+=("$e"); done
    stack=("${new[@]}")
    apply
    notify_info "Shader" "Removed: ${LABEL[$name]} · in the stack ${#stack[@]} (・_・)"
  else
    make_room_for "$name"
    stack+=("$name")
    apply
    notify_info "Shader" "Added: ${LABEL[$name]} · in the stack ${#stack[@]} （-＾〇＾-）"
  fi
}

clear_stack() {
  stack=()
  apply
  notify_info "Shader" "Effects reset (★^O^★)"
}

cmd_effect() {
  load_state
  case "${1:-}" in
    push) push_effect "${2:?effect name required}" ;;
    set) set_single "${2:?effect name required}" ;;
    toggle | off-or) toggle_effect "${2:?effect name required}" ;;
    clear | off | none) clear_stack ;;
    next | prev)
      local cur="none" idx step n
      [[ ${#stack[@]} -gt 0 ]] && cur="${stack[-1]}"
      idx=$(effect_index "$cur")
      n=${#EFFECTS[@]}
      if [[ "$1" == "next" ]]; then step=1; else step=$((n - 1)); fi
      set_single "${EFFECTS[$(((idx + step) % n))]}"
      ;;
    *)
      notify_error "Usage: effect push|set|toggle|clear|next|prev <name>"
      exit 1
      ;;
  esac
}

cmd_bright() {
  # flock -n: on fast scrolling waybar sends dozens of calls in parallel. A
  # blocking flock queues them → the queue piles up → a hang. Non-blocking: if
  # another instance is already running — exit silently, and the atomic write in
  # emit_shader guarantees Hyprland won't see a broken shader even without serialization
  exec 8>"$RUNTIME_DIR/bright.lock"
  flock -n 8 || exit 0
  load_state
  local step="0.05"
  case "${1:-}" in
    up) bright=$(awk -v b="$bright" -v s="$step" 'BEGIN{v=b+s; if(v>2)v=2;    printf "%.2f", v}') ;;
    down) bright=$(awk -v b="$bright" -v s="$step" 'BEGIN{v=b-s; if(v<0.1)v=0.1; printf "%.2f", v}') ;;
    reset) bright="1.00" ;;
    toggle) if [[ "$bright" == "1.00" ]]; then bright="0.50"; else bright="1.00"; fi ;;
    set) bright=$(awk -v b="${2:?value required}" 'BEGIN{v=b; if(v>2)v=2; if(v<0.1)v=0.1; printf "%.2f", v}') ;;
    get)
      awk -v b="$bright" 'BEGIN{printf "%d", b*100}'
      return 0
      ;;
    *)
      notify_error "Usage: bright up|down|reset|toggle|set <0.10..2.00> | get"
      exit 1
      ;;
  esac
  apply
  # Synchronous tag: while holding the key one popup updates instead of spamming the feed
  command -v notify-send >/dev/null 2>&1 && notify-send -u low \
    -h string:x-canonical-private-synchronous:screen-shader-bright \
    "Brightness" "Brightness: $(awk -v b="$bright" 'BEGIN{printf "%d", b*100}')% ☀" || true
}

# A temporary effect for N seconds, COMPOSITED over the current stack. Durable
# state is not touched — a crash mid-flash breaks nothing. Writes to a separate
# flash.frag, not touching the active-0/1 slots: the restore path after flash is
# guaranteed to differ, Hyprland re-reads the shader. Concurrent flashes are
# suppressed by flock; -k — exit silently if the stack is non-empty
cmd_flash() {
  SHADER_NO_SIGNAL=1
  local keep=""
  if [[ "${1:-}" == "-k" ]]; then
    keep=1
    shift
  fi
  local name="${1:?effect name required}" dur="${2:-1.0}"
  require_effect "$name"

  exec 9>"$RUNTIME_DIR/.flash.lock"
  flock -n 9 || exit 0

  load_state
  [[ -n "$keep" && ${#stack[@]} -gt 0 ]] && exit 0

  local file="$RUNTIME_DIR/flash.frag"
  if is_raw "$name"; then
    # Nothing to compose with — the raw shader is the whole frame for its second
    frag_body "${FILE[$name]}" >"$file"
  else
    # The flash body first (usually samples the texture itself — glitch/wave); from
    # the stack we take into the chain only color ones (not sampling the texture) —
    # otherwise they'd overwrite the flash result (a proper composition of several
    # geometries needs multi-pass rendering, and Hyprland has one slot)
    local bodies=("${FILE[$name]}") e
    for e in "${stack[@]}"; do
      is_raw "$e" && continue
      samples_texture "$e" || bodies+=("${FILE[$e]}")
    done
    emit_shader "$file" "${bodies[@]}"
  fi

  # Render mode over the whole pair (flash + stack)
  set_render_mode "$(render_mode_for "$name" "${stack[@]}")"

  hyprctl keyword decoration:screen_shader "$file" >/dev/null
  sleep "$dur"
  load_state
  apply
}

cmd_restore() {
  # Don't signal waybar at session start (see signal_waybar); the script exits
  # right away, so setting the flag globally is safe
  SHADER_NO_SIGNAL=1
  load_state
  apply
}

# JSON for a waybar custom module: emojis of all stack effects + brightness percent
cmd_status() {
  load_state
  local pct emoji="" labels="" e class
  pct=$(awk -v b="$bright" 'BEGIN{printf "%d", b * 100}')
  for e in "${stack[@]}"; do
    emoji+="${EMOJI[$e]:-🎬}"
    labels+="${LABEL[$e]:-$e} + "
  done
  labels="${labels% + }"
  if [[ ${#stack[@]} -gt 1 ]]; then class="stack"; elif [[ ${#stack[@]} -eq 1 ]]; then class="${stack[0]}"; else class="dim"; fi

  if [[ ${#stack[@]} -eq 0 && "$bright" == "1.00" ]]; then
    # Nothing active — the module hides (empty text)
    printf '{"text":"","tooltip":"","class":"off"}\n'
  elif [[ ${#stack[@]} -eq 0 ]]; then
    printf '{"text":"🔅 %s%%","tooltip":"Brightness %s%%","class":"dim"}\n' "$pct" "$pct"
  elif [[ "$bright" == "1.00" ]]; then
    printf '{"text":"%s","tooltip":"%s","class":"%s"}\n' "$emoji" "$labels" "$class"
  else
    printf '{"text":"%s %s%%","tooltip":"%s · brightness %s%%","class":"%s"}\n' \
      "$emoji" "$pct" "$labels" "$pct" "$class"
  fi
}

# List "<emoji> <label>|<value>" in menu order — the single source of truth for the
# rofi picker (rofi-shader.sh reads exactly this). Active ones in the stack are
# marked with an apply number in the "01. " format (stack order = the order in
# which effects were added), to see the accumulated composition and its order
cmd_menu() {
  load_state
  local e mark pos
  for e in "${EFFECTS[@]}"; do
    if [[ "$e" != "none" ]] && pos=$(stack_position "$e"); then
      mark=$(printf '%02d. ' "$pos")
    else
      mark=""
    fi
    printf '%s%s %s|%s\n' "$mark" "${EMOJI[$e]}" "${LABEL[$e]}" "$e"
  done
}

# Install an effect into the writable directory. The flags are written as header lines
# ON TOP of the file, and the same keys are dropped from the copy below — so a shader
# that knows nothing about this manager still lands with the header it needs, and one
# that carries its own keeps whatever the flags do not override
cmd_add() {
  local src="" name="" force="" k
  local -A given=()
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --name)
        name="${2:?--name needs a value}"
        shift 2
        ;;
      --label | --emoji | --order)
        given["${1#--}"]="${2:?$1 needs a value}"
        shift 2
        ;;
      --animated | --samples | --raw)
        given["${1#--}"]="yes"
        shift
        ;;
      --no-animated | --no-samples | --no-raw)
        given["${1#--no-}"]="no"
        shift
        ;;
      -f | --force)
        force=1
        shift
        ;;
      -*)
        notify_error "Unknown flag: $1"
        exit 1
        ;;
      *)
        src="$1"
        shift
        ;;
    esac
  done

  [[ -n "$src" ]] || {
    notify_error "Usage: add <file.frag> [--name n] [--label L] [--emoji E] [--order N] [--animated] [--samples] [--raw] [-f]"
    exit 1
  }
  [[ -f "$src" ]] || {
    notify_error "No such file: $src"
    exit 1
  }

  name="${name:-$(basename "$src" .frag)}"
  [[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9_-]*$ ]] || {
    notify_error "Bad effect name: $name (letters, digits, - and _)"
    exit 1
  }

  # The one time the GLSL is looked at: a mismatch here is worth catching now rather
  # than as a screen that quietly does not change
  local raw="${given[raw]:-}"
  if [[ -z "$raw" ]]; then
    if grep -qiE '^[[:space:]]*//[[:space:]]*raw[[:space:]]*:[[:space:]]*(yes|true|on|1)[[:space:]]*$' "$src"; then
      raw="yes"
    else
      raw="no"
    fi
  fi
  if [[ "$raw" == "yes" ]]; then
    grep -qE '(^|[^A-Za-z0-9_])main[[:space:]]*\(' "$src" || {
      notify_error "--raw expects a standalone shader with its own main(); $src has none"
      exit 1
    }
  else
    if grep -qE '(^|[^A-Za-z0-9_])main[[:space:]]*\(' "$src"; then
      notify_error "$src defines main(): add it with --raw, or rewrite it as vec3 effect(vec3 c, vec2 uv)"
      exit 1
    fi
    grep -qE 'vec3[[:space:]]+effect[[:space:]]*\(' "$src" || {
      notify_error "$src has no vec3 effect(vec3 c, vec2 uv) — that function is the entry point"
      exit 1
    }
  fi

  local target="$USER_DIR/$name.frag"
  if [[ -e "$target" && -z "$force" ]]; then
    notify_error "Already added: $name — pass -f to replace it"
    exit 1
  fi

  mkdir -p "$USER_DIR"
  local tmp="$target.tmp.$$"
  {
    # Fixed key order, so the same flags always produce the same file
    for k in label emoji order animated samples raw; do
      [[ -n "${given[$k]:-}" ]] && printf '// %s: %s\n' "$k" "${given[$k]}"
    done
    if [[ ${#given[@]} -gt 0 ]]; then
      local drop=""
      for k in "${!given[@]}"; do drop+="${drop:+|}$k"; done
      sed -E "/^[[:space:]]*\/\/[[:space:]]*($drop)[[:space:]]*:/d" "$src"
    else
      cat "$src"
    fi
  } >"$tmp"
  mv -f "$tmp" "$target"

  local shadowed=""
  [[ -f "$SHADER_DIR/$name.frag" ]] && shadowed=" · replaces the installed one"
  notify_info "Shader" "Added: $name$shadowed （-＾〇＾-）"
  printf '%s\n' "$target"
}

# Drop an added effect. Only the writable directory is ours to delete from — an
# installed effect comes with the package, and removing its runtime copy just uncovers it
cmd_remove() {
  local name="${1:?effect name required}"
  local target="$USER_DIR/$name.frag"
  if [[ ! -f "$target" ]]; then
    if [[ -n "${FILE[$name]:-}" ]]; then
      notify_error "$name comes with the package, it was not added at runtime"
    else
      notify_error "Unknown effect: $name"
    fi
    exit 1
  fi
  rm -f "$target"

  EFFECTS=()
  unset EMOJI LABEL ANIMATED SAMPLES RAW FILE
  declare -gA EMOJI LABEL ANIMATED SAMPLES RAW FILE
  load_effects

  # An effect that is gone for good must leave the stack too, or the next apply
  # looks for a file that is not there
  load_state
  if [[ -z "${FILE[$name]:-}" ]] && in_list "$name" "${stack[@]}"; then
    local e new=()
    for e in "${stack[@]}"; do [[ "$e" == "$name" ]] || new+=("$e"); done
    stack=("${new[@]}")
    apply
  fi
  if [[ -n "${FILE[$name]:-}" ]]; then
    notify_info "Shader" "Removed the added $name · the installed one is back (・_・)"
  else
    notify_info "Shader" "Removed: $name (・_・)"
  fi
}

# Full reset: effects + brightness in one apply (for waybar RMB)
cmd_reset_all() {
  load_state
  stack=()
  bright="1.00"
  apply
  notify_info "Shader" "Effects and brightness reset (★^O^★)"
}

case "${1:-}" in
  help | -h | --help)
    usage
    exit 0
    ;;
esac

mkdir -p "$RUNTIME_DIR"
load_effects

case "${1:-}" in
  effect)
    shift
    cmd_effect "$@"
    ;;
  bright)
    shift
    cmd_bright "$@"
    ;;
  flash)
    shift
    cmd_flash "$@"
    ;;
  add)
    shift
    cmd_add "$@"
    ;;
  remove | rm)
    shift
    cmd_remove "$@"
    ;;
  restore) cmd_restore ;;
  reset-all) cmd_reset_all ;;
  status) cmd_status ;;
  menu) cmd_menu ;;
  *)
    usage >&2
    notify_error "Usage: screen-shader effect|bright|flash|add|remove|reset-all|restore|status|menu|help"
    exit 1
    ;;
esac
