# screen-shader plus its effects, the UI layer that opens the picker, and the modi that
# fills it. This points every one of them at the others by absolute path and puts the
# runtime tools on PATH. hyprctl and rofi are deliberately NOT runtime inputs: both come
# from the running session, and pinning a second rofi here would shadow the user's own
{
  lib,
  stdenvNoCC,
  installShellFiles,
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
  versionFile = builtins.path {
    name = "screen-shader-VERSION";
    path = ../VERSION;
  };
  picker = builtins.path {
    name = "rofi-shader.sh";
    path = ../rofi-shader.sh;
  };
  modi = builtins.path {
    name = "shader-modi.sh";
    path = ../shader-modi.sh;
  };
  shaders = builtins.path {
    name = "screen-shader-shaders";
    path = ../shaders;
  };
  bashCompletion = builtins.path {
    name = "screen-shader.bash";
    path = ../completions/screen-shader.bash;
  };
  zshCompletion = builtins.path {
    name = "_screen-shader";
    path = ../completions/_screen-shader;
  };

  # Left empty when unset, so the script's own default stays the single source of it
  promptArg = lib.optionalString (
    rofiPrompt != null
  ) ''--set-default ROFI_SHADER_PROMPT "${rofiPrompt}"'';
  signalArg = lib.optionalString (
    waybarSignal != null
  ) ''--set-default WAYBAR_SHADER_SIGNAL "${toString waybarSignal}"'';

  # The manager's own tools. libnotify is deliberately not among them: it belongs to the
  # UI layer, and the manager only ever writes text to stderr
  runtimeInputs = [
    coreutils
    gawk
    gnugrep
    gnused
    procps
    util-linux
  ];
in

stdenvNoCC.mkDerivation {
  pname = "screen-shader";
  # VERSION is the one place the number lives; CI holds CHANGELOG.md to it
  version = lib.fileContents ../VERSION;

  dontUnpack = true;
  nativeBuildInputs = [
    installShellFiles
    makeWrapper
  ];
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

    # --version finds this one prefix over from the wrapped script in bin
    install -Dm644 ${versionFile} $out/share/screen-shader/VERSION

    install -Dm755 ${script} $out/bin/screen-shader
    install -Dm755 ${picker} $out/bin/rofi-shader
    # libexec, not bin: rofi runs the modi, a human never does
    install -Dm755 ${modi} $out/libexec/shader-modi
    patchShebangs $out/bin $out/libexec

    installShellCompletion --bash --name screen-shader ${bashCompletion}
    installShellCompletion --zsh --name _screen-shader ${zshCompletion}

    # --set-default, not --set: an override from the caller's environment still wins
    wrapProgram $out/bin/screen-shader \
      --prefix PATH : ${lib.makeBinPath runtimeInputs} \
      --set-default SCREEN_SHADER_DIR "$dir" ${signalArg}
    wrapProgram $out/bin/rofi-shader \
      --prefix PATH : ${lib.makeBinPath (runtimeInputs ++ [ libnotify ])} \
      --set-default SCREEN_SHADER $out/bin/screen-shader \
      --set-default SCREEN_SHADER_MODI $out/libexec/shader-modi
    wrapProgram $out/libexec/shader-modi \
      --prefix PATH : ${lib.makeBinPath runtimeInputs} \
      --set-default SCREEN_SHADER_UI $out/bin/rofi-shader ${promptArg}

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
