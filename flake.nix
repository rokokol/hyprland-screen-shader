{
  description = "Stacking full-screen effects and software brightness for Hyprland";

  inputs.nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";

  outputs =
    { self, nixpkgs }:
    let
      lib = nixpkgs.lib;
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      forAllSystems = f: lib.genAttrs systems (system: f nixpkgs.legacyPackages.${system});

      # Each piece isolated, so a README edit doesn't rebuild anything
      manager = builtins.path {
        name = "screen-shader.sh";
        path = ./screen-shader.sh;
      };
      picker = builtins.path {
        name = "rofi-shader.sh";
        path = ./rofi-shader.sh;
      };
      installer = builtins.path {
        name = "install.sh";
        path = ./install.sh;
      };
      shaderDir = builtins.path {
        name = "screen-shader-shaders";
        path = ./shaders;
      };
      testsDir = builtins.path {
        name = "screen-shader-tests";
        path = ./tests;
      };
    in
    {
      packages = forAllSystems (pkgs: rec {
        default = screen-shader;
        screen-shader = pkgs.callPackage ./nix/package.nix { };
      });

      homeManagerModules.default = import ./nix/module.nix { inherit self; };

      checks = forAllSystems (
        pkgs:
        let
          screen-shader = self.packages.${pkgs.stdenv.hostPlatform.system}.screen-shader;
        in
        {
          # The behaviour suite, run against the scripts as they sit in the tree
          tests =
            pkgs.runCommand "tests"
              {
                nativeBuildInputs = with pkgs; [
                  bash
                  coreutils
                  diffutils
                  gawk
                  gnugrep
                  gnused
                  util-linux
                ];
              }
              ''
                export HOME=$PWD
                mkdir -p repo
                cp ${manager} repo/screen-shader.sh
                cp ${picker} repo/rofi-shader.sh
                cp -r ${shaderDir} repo/shaders
                cp -r ${testsDir} repo/tests
                chmod -R +w repo
                patchShebangs repo
                bash repo/tests/run.sh
                touch $out
              '';

          # Every effect compiles alone, then all of them at once — the composition is
          # where a name collision between two effect bodies would surface
          shaders-compile =
            pkgs.runCommand "shaders-compile"
              {
                nativeBuildInputs = [
                  pkgs.glslang
                  screen-shader
                ];
              }
              ''
                export HOME=$PWD XDG_RUNTIME_DIR=$PWD/rt SCREEN_SHADER_STATE=$PWD/state
                mkdir -p stub "$XDG_RUNTIME_DIR"
                # The manager drives a live compositor; a stub is all it takes to make it emit GLSL
                printf '#!/bin/sh\nexit 0\n' >stub/hyprctl
                chmod +x stub/hyprctl
                export PATH=$PWD/stub:$PATH

                check() {
                  printf 'stack=(%s)\nbright=0.80\nslot=0\n' "$*" >"$SCREEN_SHADER_STATE"
                  screen-shader restore
                  for f in "$XDG_RUNTIME_DIR"/screen-shader/active-*.frag; do
                    glslangValidator -S frag "$f" || { echo "^ failed for stack: $*"; exit 1; }
                    rm -f "$f"
                  done
                }

                names=$(screen-shader menu | cut -d'|' -f2)
                for n in $names; do check "$n"; done
                # shellcheck disable=SC2086
                check $names
                touch $out
              '';

          # The header is an effect's whole contract — with the picker and with the
          # compositor. Omitting a key is legal for a dropped-in shader, which then gets
          # the defaults; in here it is a mistake
          shaders-metadata = pkgs.runCommand "shaders-metadata" { } ''
            for f in ${shaderDir}/*.frag; do
              for key in label emoji order animated samples; do
                grep -qE "^//[[:space:]]*$key:" "$f" ||
                  { echo "$(basename "$f"): missing '// $key:' header"; exit 1; }
              done
            done
            touch $out
          '';

          # "// animated:" is a claim; the compiler is the authority. Reflection lists only
          # live uniforms, so "time" in it means the effect really moves — and one that
          # moves without saying so renders frozen, the single header mistake that shows
          # on screen. Claiming more than you need stays legal: it only costs redraws
          shaders-render-class =
            pkgs.runCommand "shaders-render-class"
              {
                nativeBuildInputs = [
                  pkgs.glslang
                  pkgs.gnugrep
                  screen-shader
                ];
              }
              ''
                export HOME=$PWD XDG_RUNTIME_DIR=$PWD/rt SCREEN_SHADER_STATE=$PWD/state
                mkdir -p stub "$XDG_RUNTIME_DIR"
                printf '#!/bin/sh\nprintf "%%s\\n" "$*" >>"$CALLS"\n' >stub/hyprctl
                chmod +x stub/hyprctl
                export PATH=$PWD/stub:$PATH CALLS=$PWD/calls

                for n in $(screen-shader menu | cut -d'|' -f2); do
                  rm -f "$XDG_RUNTIME_DIR"/screen-shader/*.frag
                  : >"$CALLS"
                  printf 'stack=(%s)\nbright=1.00\nslot=0\n' "$n" >"$SCREEN_SHADER_STATE"
                  screen-shader restore

                  glslangValidator -S frag -l -q "$XDG_RUNTIME_DIR"/screen-shader/active-*.frag >refl
                  moves=$(grep -c '^time:' refl || true)
                  told=$(grep -c 'damage_tracking 0' "$CALLS" || true)
                  if [ "$moves" -gt 0 ] && [ "$told" -eq 0 ]; then
                    echo "$n: the compiler keeps uniform time live, but the effect is not classified animated"
                    exit 1
                  fi
                done
                touch $out
              '';

          # The wrappers are the whole difference between the repo and the package:
          # they are what makes the effects findable and the picker self-contained
          package-smoke =
            pkgs.runCommand "package-smoke"
              {
                nativeBuildInputs = [
                  screen-shader
                  pkgs.gnugrep
                ];
              }
              ''
                export HOME=$PWD XDG_RUNTIME_DIR=$PWD SCREEN_SHADER_STATE=$PWD/state
                # No grep -q on a pipe: it closes the pipe early and the writer sees EPIPE
                screen-shader menu | grep -xF '🌈 Normal|none' >/dev/null
                screen-shader help | grep SCREEN_SHADER_DIR >/dev/null
                screen-shader status | grep '"class":"off"' >/dev/null
                # The picker must name its own rofi mode, without anything in rofi.rasi
                ROFI_RETV=0 rofi-shader | tr '\000\037' '@|' | grep -F '@prompt|📺' >/dev/null
                touch $out
              '';

          # Enabling the module has to be enough to get keys, picker and indicator
          module-wiring =
            let
              wiring = import ./nix/module-test.nix {
                inherit lib pkgs;
                module = self.homeManagerModules.default;
              };
            in
            pkgs.runCommand "module-wiring"
              {
                nativeBuildInputs = [ pkgs.jq ];
                dump = builtins.toJSON wiring;
                passAsFile = [ "dump" ];
              }
              ''
                want() { jq -e "$1" "$dumpPath" >/dev/null || { echo "module wiring: $2"; exit 1; }; }

                want '.hyprland.bind | any(test("bin/rofi-shader"))' "the picker is not bound"
                want '.hyprland.bind | any(test("SUPER, G, exec, .*effect clear"))' "clearing is not bound"
                want '.hyprland.bindel | length == 2' "brightness is not held-repeatable"
                want '.hyprland.exec | any(test("bin/screen-shader restore"))' "the shader is not restored on reload"
                want '.waybar.mainBar["custom/shader"].signal == 8' "the indicator got no signal number"
                want '.waybar.mainBar["custom/shader"]["on-click"] | test("bin/rofi-shader")' "clicking the indicator opens nothing"
                want '.package | test("screen-shader")' "no package installed"

                # …and none of it leaks into a config that did not ask for it
                want '.bareHyprland == {}' "binds appear without Hyprland"
                want '.bareWaybar == {}' "a bar is touched without being named"
                want '.offPackages == []' "the package is installed while disabled"
                want '.offHyprland == {}' "binds survive enable = false"
                touch $out
              '';

          scripts-lint =
            pkgs.runCommand "scripts-lint"
              {
                nativeBuildInputs = [
                  pkgs.shellcheck
                  pkgs.shfmt
                ];
              }
              ''
                shellcheck ${manager} ${picker} ${installer} ${testsDir}/run.sh
                shfmt -d -i 2 -ci ${manager} ${picker} ${installer} ${testsDir}/run.sh
                touch $out
              '';
        }
      );

      devShells = forAllSystems (pkgs: {
        default = pkgs.mkShell {
          packages = with pkgs; [
            glslang
            shellcheck
            shfmt
          ];
        };
      });

      formatter = forAllSystems (pkgs: pkgs.nixfmt-tree);
    };
}
