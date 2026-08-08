# Home Manager module. Enabling it is meant to be enough: the keys are bound, the
# picker knows its own rofi modi, and the waybar module is defined. Where the
# indicator sits in the bar stays the user's call — that one nobody can guess
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
  mod = cfg.hyprland.modifier;
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
        Effects merged into the shader directory, keyed by effect name. Give a .frag
        path or the GLSL itself — one function `vec3 effect(vec3 c, vec2 uv)` under a
        `// label:` / `// emoji:` / `// order:` header. A name that already exists
        replaces the shipped effect
      '';
    };

    rofi.prompt = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "🎬";
      description = ''
        What rofi shows as the mode name (`-display-shader`). The picker passes it
        itself, so nothing has to be declared in the rofi config
      '';
    };

    waybar = {
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
        default = {
          exec = "${exe} status";
          return-type = "json";
          format = "{}";
          on-click = picker;
          on-click-right = "${exe} reset-all";
          on-click-middle = "${exe} bright toggle";
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
        description = "Bind the keys and re-apply the shader on every Hyprland reload";
      };

      modifier = lib.mkOption {
        type = lib.types.str;
        default = "SUPER";
        description = ''
          Modifier for the default bindings, spelled out rather than taken from a
          hyprland variable — these lines are emitted before your own config is sourced,
          so a `$mainMod` defined there does not exist yet
        '';
      };

      settings = lib.mkOption {
        type = lib.types.attrsOf lib.types.anything;
        default = {
          bind = [
            "${mod}, G, exec, ${exe} effect clear"
            "${mod} SHIFT, G, exec, ${picker}"
            "${mod} CTRL, BackSpace, exec, ${exe} bright reset"
          ];
          # bindel repeats while the key is held, which is what makes dimming feel continuous
          bindel = [
            "${mod} CTRL, bracketright, exec, ${exe} bright up"
            "${mod} CTRL, bracketleft, exec, ${exe} bright down"
          ];
          # exec, not exec-once: the shader slot is runtime state and is lost on every reload
          exec = [ "${exe} restore" ];
        };
        defaultText = lib.literalExpression "the bindings listed in the README";
        description = ''
          Merged into `wayland.windowManager.hyprland.settings`. Set to `{ }` to bind
          everything yourself
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

      {
        programs.waybar.settings = lib.genAttrs cfg.waybar.bars (_: {
          "custom/shader" = cfg.waybar.module;
        });
      }
    ]
  );
}
