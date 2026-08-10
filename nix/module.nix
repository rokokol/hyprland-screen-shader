# Home Manager module. It installs the package, re-applies the shader on every Hyprland
# reload, and defines the waybar module for the bars that ask for it. The keys are yours
# to bind — `rofi-shader` and `screen-shader …` are whole commands
{ self }:
{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.programs.screen-shader;
  exe = lib.getExe cfg.package;
  picker = "${cfg.package}/bin/rofi-shader";
in
{
  options.programs.screen-shader = {
    enable = lib.mkEnableOption "the Hyprland full-screen shader and brightness manager";

    package = lib.mkOption {
      type = lib.types.package;
      default = self.packages.${pkgs.stdenv.hostPlatform.system}.screen-shader.override {
        inherit (cfg) extraShaders;
        rofiPrompt = cfg.rofi.prompt;
        waybarSignal = cfg.waybar.signal;
      };
      defaultText = lib.literalExpression "screen-shader carrying extraShaders and the settings below";
      description = "The package to install; it carries its own effects";
    };

    extraShaders = lib.mkOption {
      type = lib.types.attrsOf (lib.types.either lib.types.path lib.types.lines);
      default = { };
      example = lib.literalExpression "{ bloom = ./bloom.frag; }";
      description = ''
        Effects merged into the installed shader directory, keyed by effect name. Give
        a .frag path or the GLSL itself — one function `vec3 effect(vec3 c, vec2 uv)`
        under a `// label:` / `// emoji:` / `// order:` header, plus `// animated:`,
        `// samples:` and `// raw:` where they apply. A name that already exists
        replaces the shipped effect.

        This is the declarative half. Its counterpart is `screen-shader add`, which
        writes to $XDG_DATA_HOME/screen-shader/shaders at runtime and wins on a name
        collision — that directory is user data and a rebuild does not touch it
      '';
    };

    rofi.prompt = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "🎬";
      description = ''
        What rofi shows as the mode name. The picker sets it through the script
        protocol, so nothing has to be declared in the rofi config
      '';
    };

    waybar = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = false;
        description = ''
          Define the `custom/shader` module in the bars listed below. Off by default and
          declared rather than guessed from an empty `bars` list — a module that writes
          into someone else's bar should be asked for
        '';
      };

      signal = lib.mkOption {
        type = lib.types.nullOr lib.types.int;
        default = null;
        example = 8;
        description = ''
          `SIGRTMIN+N` the indicator refreshes on. Baked into the package, so the
          script and the module cannot disagree about the number. Null never pokes
          waybar — leave it null if no indicator is shown
        '';
      };

      bars = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        example = [ "mainBar" ];
        description = ''
          Bars in `programs.waybar.settings` that get a `custom/shader` definition.
          Listing the module in that bar's `modules-left/center/right` is still up to
          you — only you know where it belongs
        '';
      };

      module = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        readOnly = true;
        # A popup belongs where nothing else answers. The clicks change a lot at once
        # and go through the UI layer; scrolling does not, because the number moving
        # under the cursor is the answer
        default = {
          exec = "${exe} status";
          return-type = "json";
          format = "{}";
          on-click = picker;
          on-click-right = "${picker} reset-all";
          on-click-middle = "${picker} bright toggle";
          on-scroll-up = "${exe} bright up";
          on-scroll-down = "${exe} bright down";
        }
        // lib.optionalAttrs (cfg.waybar.signal != null) { inherit (cfg.waybar) signal; };
        description = "The `custom/shader` definition, for placing it in a bar by hand";
      };
    };

    hyprland = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = config.wayland.windowManager.hyprland.enable;
        defaultText = lib.literalExpression "config.wayland.windowManager.hyprland.enable";
        description = "Re-apply the shader on every Hyprland reload";
      };

      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {
          # exec, not exec-once: the shader slot is runtime state and is lost on every
          # reload. This is the one line the module still writes into your Hyprland
          # config, because it is not a taste — without it an active effect quietly
          # falls off. Keys are yours, see the README
          exec = [ "${exe} restore" ];
        };
        defaultText = lib.literalExpression ''{ exec = [ "screen-shader restore" ]; }'';
        description = ''
          Merged into `wayland.windowManager.hyprland.settings`. Set to `{ }` to write
          even that line yourself
        '';
      };
    };
  };

  config = lib.mkIf cfg.enable (
    lib.mkMerge [
      { home.packages = [ cfg.package ]; }

      (lib.mkIf cfg.hyprland.enable {
        wayland.windowManager.hyprland.settings = cfg.hyprland.settings;
      })

      (lib.mkIf cfg.waybar.enable {
        programs.waybar.settings = lib.genAttrs cfg.waybar.bars (_: {
          "custom/shader" = cfg.waybar.module;
        });
      })
    ]
  );
}
