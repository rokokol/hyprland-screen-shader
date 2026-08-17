# Changelog

Kept in the shape of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioned by [semver](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

### Fixed

- the Nix package version follows the latest release instead of the pre-release script version

## [1.0.1] - 2026-08-14

### Fixed

- `tests/live.sh` puts the session's state file back: `restore` re-applies whatever the loop last wrote, so a run used to leave the last effect switched on
- `tests/live.sh` no longer claims to check for compile errors in `hyprland.log` — measured on Hyprland 0.56.1, a refused shader appears only on the on-screen error bar, so that assertion could never fail

## [1.0.0] - 2026-08-13

Split out of [rokokol/huix](https://github.com/rokokol/huix), where it was a script and a pile of `.frag` files under the Hyprland directory

### Added

- the manager: one shader slot shared by a stack of effects plus a brightness multiplier, assembled into a single generated shader
- fourteen effects, one file each, and `add`/`remove` for your own
- software brightness, which goes below the hardware minimum and above 100%
- the rofi picker as a script-modi, and `status` for a waybar module
- `homeModules.default` (`programs.screen-shader`) and `overlays.default`
- checks: the suite against a stub hyprctl with golden shaders, every effect compiled alone and composed, header metadata, the packaged wrappers, module wiring
