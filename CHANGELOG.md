# Changelog

Kept in the shape of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioned by [semver](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

## [1.0.0] - 2026-08-13

Split out of [rokokol/huix](https://github.com/rokokol/huix), where it was a script and a pile of `.frag` files under the Hyprland directory

### Added

- the manager: one shader slot shared by a stack of effects plus a brightness multiplier, assembled into a single generated shader
- fourteen effects, one file each, and `add`/`remove` for your own
- software brightness, which goes below the hardware minimum and above 100%
- the rofi picker as a script-modi, and `status` for a waybar module
- `homeModules.default` (`programs.screen-shader`) and `overlays.default`
- checks: the suite against a stub hyprctl with golden shaders, every effect compiled alone and composed, header metadata, the packaged wrappers, module wiring
