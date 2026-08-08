# screen-shader plus its effects. The scripts self-locate their shaders/ directory,
# so this only has to point SCREEN_SHADER_DIR at the store copy and put the runtime
# tools on PATH. hyprctl and rofi are deliberately NOT runtime inputs: both come from
# the running session, and pinning a second rofi here would shadow the user's own
{
  lib,
  stdenvNoCC,
  makeWrapper,
  writeText,
  bash,
  coreutils,
  gawk,
  gnugrep,
  gnused,
  libnotify,
  procps,
  util-linux,
  # Effects merged into the shader directory, keyed by name: a .frag path or the GLSL itself
  extraShaders ? { },
  # Baked into the wrappers rather than exported as session variables, so a change to
  # either lands on the next rebuild instead of the next login
  rofiPrompt ? null,
  waybarSignal ? null,
}:

let
  # Each piece isolated, so editing the README doesn't rebuild the package
  script = builtins.path {
    name = "screen-shader.sh";
    path = ../screen-shader.sh;
  };
  picker = builtins.path {
    name = "rofi-shader.sh";
    path = ../rofi-shader.sh;
  };
  shaders = builtins.path {
    name = "screen-shader-shaders";
    path = ../shaders;
  };

  # Left empty when unset, so the script's own default stays the single source of it
  promptArg = lib.optionalString (
    rofiPrompt != null
  ) ''--set-default ROFI_SHADER_PROMPT "${rofiPrompt}"'';
  signalArg = lib.optionalString (
    waybarSignal != null
  ) ''--set-default WAYBAR_SHADER_SIGNAL "${toString waybarSignal}"'';

  runtimeInputs = [
    coreutils
    gawk
    gnugrep
    gnused
    libnotify
    procps
    util-linux
  ];
in

stdenvNoCC.mkDerivation {
  pname = "screen-shader";
  version = "1.0";

  dontUnpack = true;
  nativeBuildInputs = [ makeWrapper ];
  buildInputs = [ bash ];

  installPhase = ''
    runHook preInstall

    dir=$out/share/screen-shader/shaders
    mkdir -p "$dir"
    cp ${shaders}/*.frag "$dir"
    ${lib.concatLines (
      lib.mapAttrsToList (
        name: v: "cp ${if builtins.isPath v then v else writeText "${name}.frag" v} \"$dir/${name}.frag\""
      ) extraShaders
    )}
    chmod +w "$dir"/*.frag

    install -Dm755 ${script} $out/bin/screen-shader
    install -Dm755 ${picker} $out/bin/rofi-shader
    patchShebangs $out/bin

    # --set-default, not --set: an override from the caller's environment still wins
    wrapProgram $out/bin/screen-shader \
      --prefix PATH : ${lib.makeBinPath runtimeInputs} \
      --set-default SCREEN_SHADER_DIR "$dir" ${signalArg}
    wrapProgram $out/bin/rofi-shader \
      --prefix PATH : ${lib.makeBinPath runtimeInputs} \
      --set-default SCREEN_SHADER $out/bin/screen-shader ${promptArg} ${signalArg}

    runHook postInstall
  '';

  meta = {
    description = "Stacking full-screen effects and software brightness for Hyprland";
    homepage = "https://github.com/rokokol/hyprland-screen-shader";
    license = lib.licenses.mit;
    platforms = lib.platforms.linux;
    mainProgram = "screen-shader";
  };
}
