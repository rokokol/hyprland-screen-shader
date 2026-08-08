<div align="center">

# Screen shader for Hyprland

**Stacking full-screen effects and software brightness** |･ω･｀)

![Hyprland](https://img.shields.io/badge/Hyprland-58E1FF?style=flat&logo=hyprland&logoColor=black)
![GLSL](https://img.shields.io/badge/GLSL-ES_3.0-5586A4?style=flat&logo=opengl&logoColor=white)
![Nix](https://img.shields.io/badge/Nix-flake-7EBAE4?style=flat&logo=nixos&logoColor=white)
[![license](https://img.shields.io/badge/MIT-3DA639?style=flat)](LICENSE)
[![build](https://github.com/rokokol/hyprland-screen-shader/actions/workflows/build.yml/badge.svg)](https://github.com/rokokol/hyprland-screen-shader/actions/workflows/build.yml)

[Русский](README.ru.md)

</div>

Hyprland has exactly **one** shader slot, `decoration:screen_shader`. That means night-warmth and dimming and a CRT filter are mutually exclusive — whichever you set last wins, and the rest are gone. This manager takes the slot for itself and **composes**: each effect is one file describing only `vec3 effect(vec3 c, vec2 uv)`, and the manager assembles the active ones plus a brightness multiplier into a single generated shader

Software brightness, too: a desktop has no backlight to turn down, so dimming here is a multiply — which also means it goes below what the hardware minimum would allow, and above 100%

Came over from my rice, **[rokokol/huix](https://github.com/rokokol/huix)**

```sh
# try one on the running session without installing anything
nix run github:rokokol/hyprland-screen-shader -- flash crt 3
```

## Effects

| | | |
| --- | --- | --- |
| ⚫ `grayscale` | 🟤 `sepia` | 🔄 `invert` |
| 🌅 `warm` — cuts blue, for the evening | ❄️ `cool` | 🎯 `vignette` |
| 🔪 `sharpen` — 3×3 kernel | 🎨 `posterize` | 🌈 `none` — dimming only |
| 📺 `crt` — curvature, shadow mask, scanlines | 🟢 `matrix` — digital rain | 💾 `jpeg` — DCT blocking and ringing |
| 🌊 `wave` — a slow ripple | 📡 `glitch` — RGB split and row tearing | |

They **stack**. `effect push` adds a filter over the current ones, `effect toggle` adds or removes, `effect clear` drops everything. Effects that sample the texture at an offset (`crt`, `wave`, `glitch`, `jpeg`, `sharpen`) are chained first, colour filters after — so geometry happens once and colour grades the result. Two geometric effects can't honestly compose in one pass, so the last one wins

## Install

### Home Manager

```nix
{
  inputs.screen-shader.url = "github:rokokol/hyprland-screen-shader";

  # in your home configuration
  imports = [ inputs.screen-shader.homeManagerModules.default ];

  programs.screen-shader = {
    enable = true;
    waybar = {
      signal = 8;
      bars = [ "mainBar" ];
    };
  };
}
```

That is the whole setup. Enabling it installs the package, binds the keys, points the picker at itself as a rofi modi, and defines a `custom/shader` module in the named bars. The one thing left to you is *where* the indicator sits — add `"custom/shader"` to that bar's `modules-right` (or left, or centre; nobody can guess that one)

| key | does |
| --- | --- |
| `SUPER SHIFT + G` | the picker — every effect, plus brightness buttons |
| `SUPER + G` | clear the stack |
| `SUPER CTRL + ]` / `[` | brightness ±5%, repeats while held |
| `SUPER CTRL + Backspace` | brightness back to 100% |

Change `hyprland.modifier`, or replace `hyprland.settings` wholesale, or set it to `{ }` and bind everything yourself

### Any other distribution

```sh
git clone https://github.com/rokokol/hyprland-screen-shader
cd hyprland-screen-shader
sudo ./install.sh          # PREFIX=~/.local ./install.sh for a user install
```

Nothing is built: the scripts and the effects are copied to `$PREFIX/share/screen-shader` and symlinked into `$PREFIX/bin`. They resolve their own location through the symlink, so the effects are found without any generated path

Needs `bash`, `awk`, `sed`, `grep`, `flock`, `hyprctl`, and — for the picker — `rofi`. `notify-send` is optional; without it the messages go to stderr

Then bind the keys yourself:

```conf
bind  = SUPER SHIFT, G, exec, rofi-shader
bind  = SUPER, G, exec, screen-shader effect clear
bindel = SUPER CTRL, bracketright, exec, screen-shader bright up
bindel = SUPER CTRL, bracketleft, exec, screen-shader bright down
bind  = SUPER CTRL, BackSpace, exec, screen-shader bright reset
exec  = screen-shader restore
```

`exec`, not `exec-once`: the shader slot is runtime state, so it has to be re-applied on every reload

## Commands

```sh
screen-shader effect push|set|toggle|clear|next|prev <name>
screen-shader bright up|down|reset|toggle|set <0.10..2.00>|get
screen-shader flash [-k] <name> [seconds]   # over the current stack, state untouched
screen-shader restore                       # re-apply the saved choice
screen-shader reset-all                     # effects and brightness in one go
screen-shader status                        # JSON for a waybar custom module
screen-shader menu                          # "<emoji> <label>|<name>" for the picker
```

`flash` is for something else's use: it composites an effect over whatever is on for a second or so and puts it back, without touching durable state. `-k` makes it a no-op when the stack is already busy, so it never fights a deliberate choice

The choice — the stack and the brightness — lives in `$XDG_STATE_HOME/screen-shader/state` and survives a reboot. Generated shaders are ephemeral, in `$XDG_RUNTIME_DIR/screen-shader`

## Adding your own effect

An effect is **one file** and nothing else — there is no list to append to and no table to keep in sync. Registration is the file landing in the shader directory; the manager rescans on every invocation.

### What the file must contain

```glsl
// label: Bloom          <- what the picker shows
// emoji: 🔆             <- shown next to it, and in the waybar indicator
// order: 65             <- position in the menu and in effect next/prev

vec3 effect(vec3 c, vec2 uv) {
    vec3 blur = texture(tex, uv + vec2(0.002)).rgb;
    return max(c, blur * 0.8);
}
```

Two hard requirements:

- **exactly one function `vec3 effect(vec3 c, vec2 uv)`**, returning the new colour. It is the entry point the manager calls
- **the three header lines**, each a `//` comment with `key: value`. Miss them and the effect still works, but shows up at the bottom of the menu as 🎬 under its file name

What you get for free — do **not** declare any of it yourself:

| in scope | is |
| --- | --- |
| `c` | the colour so far: the screen, or the output of the previous effect in the stack |
| `uv` | screen coordinates, 0..1 |
| `tex` | the screen texture, for sampling somewhere other than `uv` |
| `time` | seconds since start, float |
| `BRIGHTNESS` | the current soft-brightness multiplier |

Do not write `#version`, `precision`, `in`/`out`/`uniform` declarations or `main()` — the manager emits all of them, and a second copy is a compile error. Helper functions and constants at file scope are fine and may share names with other effects: when several are composed, the later bodies are renamed (`hash` → `hash_1`).

The file name is the effect's name: `bloom.frag` gives `screen-shader effect push bloom`.

### Where to put it

| installed by | put it in |
| --- | --- |
| `install.sh` | `$PREFIX/share/screen-shader/shaders/` |
| a clone | `shaders/` in the checkout |
| Nix, one-off | `SCREEN_SHADER_DIR=~/my-shaders screen-shader effect set bloom` |
| Nix, for good | `programs.screen-shader.extraShaders.bloom = ./bloom.frag;` |

`extraShaders` merges into the shipped set, so a key that already exists **replaces** the shipped effect — that is also how you re-colour or re-order one of mine without forking.

### Checking it works

```sh
screen-shader menu | grep bloom       # confirms the header was read as you meant it
screen-shader effect set bloom        # applies it
```

A **name** you got wrong is caught loudly — the manager checks the file exists and says so. A **GLSL error is not**: Hyprland accepts a shader that fails to compile without a word (`hyprctl` answers `ok`, `getoption` reports it set, and nothing lands in `hyprland.log`), so the only symptom is the effect quietly not happening. Check it yourself:

```sh
glslangValidator -S frag "$XDG_RUNTIME_DIR"/screen-shader/active-*.frag
```

Working in a clone you get that for free: `nix flake check` compiles every effect, alone and composed with all the others, which is also the only way a name collision or a stray `main()` surfaces before you are staring at an unchanged screen.

### The one thing you never declare: how it renders

Hyprland has to be told how hard to redraw, and **that is read off your code**, not off the header:

| | when | `damage_tracking` / `vfr` | why |
| --- | --- | --- | --- |
| animated | the body uses `time` | `0` / `0` | a frame every tick; with VFR on Hyprland idles and the animation stutters |
| offset | the body calls `texture()` | `1` / `1` | offset sampling reads neighbouring areas, which precise damage has not drawn yet — redraw the whole monitor, but still sleep when idle |
| plain | neither | `2` / `1` | per-pixel, partial damage is fine |

Comments are stripped before that test, so prose mentioning `time` will not make a static effect animated. Sampling `texture()` also puts the effect **first** in the chain, ahead of the colour filters — geometry happens once, colour grades the result.

## Waybar

`waybar.bars` defines the module; place it where you want it:

```nix
programs.waybar.settings.mainBar.modules-right = [ "custom/shader" "clock" ];
```

Left click opens the picker, right click resets everything, middle click halves the brightness, scroll adjusts it. The module hides itself when no effect is on and brightness is 100%

The indicator refreshes on `SIGRTMIN+N`, with `N` from `waybar.signal` — declared once and baked into the package, so the script and the bar cannot disagree. **The default action of an RT signal is to terminate the process**, so it must never be sent before waybar has installed its handler; `screen-shader restore` deliberately sends nothing for that reason, and at session start waybar reads `status` itself anyway

## Tests

```sh
tests/run.sh              # 69 assertions, no compositor needed
tests/run.sh --update     # re-record the golden shaders after a deliberate change
```

`hyprctl` and `notify-send` are stubbed, state goes to a scratch directory, and the generated GLSL is diffed against committed golden files — so a change in how shaders are assembled shows up as a diff rather than as a surprise on the next login. `nix flake check` runs the suite plus: every effect compiled with `glslangValidator` alone and all of them composed at once, the `// label:` headers, the packaged wrappers, and the Home Manager module evaluated against option stubs

## Layout

```
screen-shader.sh   the manager: state, shader assembly, render modes, indicator
rofi-shader.sh     the picker, a rofi script-modi that also launches itself
shaders/*.frag     one effect per file
nix/               package.nix, module.nix, module-test.nix
tests/             run.sh and the golden shaders
```

## License

MIT
