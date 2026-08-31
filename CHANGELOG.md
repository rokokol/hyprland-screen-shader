# Changelog

Kept in the shape of [Keep a Changelog](https://keepachangelog.com/en/1.1.0/), versioned by [semver](https://semver.org/spec/v2.0.0.html)

## [Unreleased]

### Added

- a `VERSION` file as the one place the version lives: `nix/package.nix` reads it, `screen-shader --version`/`-v` and `./install.sh --version`/`-v` print it, and CI refuses a release whose `CHANGELOG.md` has no heading for it
- installer flags for the package's install-affecting options: repeatable `--extra-shader FILE`, and `--rofi-prompt`/`--waybar-signal`, which replace a bin symlink with a two-line wrapper exporting the default so the caller's environment still wins — the non-Nix analog of `wrapProgram --set-default`
- `--uninstall` by manifest: the install writes `share/screen-shader/install-manifest` naming every file it created, uninstall consumes it, and a re-run sweeps whatever a previous install wrote that the current flags do not — the installer is declarative
- a dependency preflight that installs nothing on its own: missing tools are named and the distribution's own install command is printed as a runnable `$` line; `hyprctl`, `rofi` and `notify-send` only warn, because they come from the session
- tab completion for `install.sh` itself (`source completions/install.sh.bash` or `.zsh`), with a drift check that fails the lint when a flag exists in only one of the three places
- distro tests: `tests/distro.sh` installs for real, as root, in `debian`/`ubuntu`/`archlinux`/`fedora` `:latest` containers by running the preflight's own printed guidance, then runs the behaviour suite against the installed copy and uninstalls by the manifest; CI runs them on every push to master and weekly, never on pull requests, with one README badge per distribution

### Changed

- the shell lint's file list lives only in the flake's `scripts-lint` check; the CI shell job builds that check instead of repeating the commands

## [1.1.0] - 2026-08-29

### Added

- bash and zsh completions, installed by the package and by `install.sh`; effect names complete live through `screen-shader menu`, and the suite checks the spelled command lists against the dispatcher's usage line

## [1.0.2] - 2026-08-18

### Changed

- `install.sh` accepts `DESTDIR` independently of `PREFIX`, so package recipes can stage its canonical layout

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
