# CLAUDE.md

## What this repo is

Hyprland has exactly one shader slot, `decoration:screen_shader`, so night warmth and dimming and a CRT filter are mutually exclusive. This manager takes the slot and composes: each effect is one file describing `vec3 effect(vec3 c, vec2 uv)`, and the manager assembles the active ones plus a brightness multiplier into a single generated shader

Three scripts: `screen-shader.sh` is the manager, `rofi-shader.sh` the UI layer, `shader-modi.sh` the picker kept off `PATH`

Two seams in `rokokol/huix`: `home-manager/desktop/hyprland/services/screen-shader.nix` enables the module, and `waybar/shader.nix` supplies the RT signal number (8) and the bar name

## Build / check

```sh
nix build
nix flake check          # tests, every shader compiles alone and composed, headers, package, module
./tests/run.sh           # against a stub hyprctl; --update re-records the golden shaders
./tests/live.sh          # every effect through the real compositor, on your own screen
PREFIX=$PWD/out ./install.sh
nix fmt -- --ci
```

## Layout

```
screen-shader.sh   the manager: state, shader assembly, render modes, indicator
rofi-shader.sh     the UI layer: opens the picker, or runs the manager and notifies
shader-modi.sh     the picker itself, a rofi script-modi kept off PATH
shaders/*.frag     one effect per file
nix/               package.nix, module.nix, module-test.nix
tests/             run.sh, live.sh and the golden shaders
```

## Things that will bite

- **an empty string option is spelled `[[EMPTY]]`.** `hyprctl keyword decoration:screen_shader "[[EMPTY]]"` is how the slot is cleared, and `hyprctl getoption` prints the same literal for one that was never set
- **a shader that fails to compile is dropped silently.** The slot reads back as set either way, so the only witness is the Hyprland log — which is what `tests/live.sh` reads. `nix flake check` compiles every effect with `glslangValidator`, but that is the compiler's opinion, not the compositor's
- **`rofi` and `hyprctl` are deliberately not `runtimeInputs`.** They come from the live session, so the package does not pin a compositor
- **the picker is a script-modi, so it must stay off `PATH`.** rofi refuses to nest, which is why composing the picker into a rofi of your own takes `--modi`

## CHANGELOG

Every user-visible change adds a bullet under `## [Unreleased]` in `CHANGELOG.md`. A release moves those bullets under a new version heading with the date, tags `v<x.y.z>` and cuts a `gh release` whose notes are that section. Dates belong in this file and nowhere else — the no-dates rule holds everywhere but here, because Keep a Changelog asks for them
