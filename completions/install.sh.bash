# shellcheck shell=bash
# Bash completion for ./install.sh. Sourced from the checkout, not installed:
#   source completions/install.sh.bash
# No dependency on the bash-completion package — everything used here is bash builtin.
#
# The flag list is written by hand on purpose and checked against install.sh by
# tests/check-completions.sh: a flag added to the installer fails the suite until it
# lands here and in the zsh file too
_install_sh_screen_shader() {
  local cur prev
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"

  local flags=(
    -h --help -v --version --prefix --destdir --uninstall
    --extra-shader --rofi-prompt --waybar-signal
  )

  case "$prev" in
    --prefix | --destdir)
      compopt -o dirnames 2>/dev/null || true
      COMPREPLY=()
      return
      ;;
    --extra-shader)
      mapfile -t COMPREPLY < <(compgen -f -X '!*.frag' -- "$cur")
      compopt -o plusdirs 2>/dev/null || true
      return
      ;;
    --rofi-prompt | --waybar-signal)
      COMPREPLY=()
      return
      ;;
  esac
  mapfile -t COMPREPLY < <(compgen -W "${flags[*]}" -- "$cur")
}
complete -F _install_sh_screen_shader install.sh ./install.sh
