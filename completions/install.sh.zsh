# Zsh completion for ./install.sh. Sourced from the checkout, not installed:
#   source completions/install.sh.zsh
# Defines the function and registers it directly — no fpath, no rehash; needs compinit
# to have run, which every interactive zsh with completion already has.
#
# The flag list is written by hand on purpose and checked against install.sh by
# tests/check-completions.sh — same discipline as the bash file
_install_sh_screen_shader() {
  _arguments \
    '(-h --help)'{-h,--help}'[show help and exit]' \
    '(-v --version)'{-v,--version}'[print the version and exit]' \
    '--prefix[install prefix]:directory:_files -/' \
    '--destdir[staging root]:directory:_files -/' \
    '--uninstall[remove a previous install by its manifest]' \
    '*--extra-shader[install an additional .frag effect]:file:_files -g "*.frag"' \
    '--rofi-prompt[bake a default picker prompt into bin/rofi-shader]:prompt:' \
    '--waybar-signal[bake a default waybar RT signal into bin/screen-shader]:number:'
}
compdef _install_sh_screen_shader install.sh
