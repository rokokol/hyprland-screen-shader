# shellcheck shell=bash
# Bash completion for ./install.sh. Sourced from the checkout, not installed:
#   source completions/install.sh.bash
# No dependency on the bash-completion package — everything used here is bash builtin,
# and nothing newer than the bash 3.2 a stock macOS sources it with.
#
# The flag list is written by hand on purpose and checked against install.sh by
# check-sh.sh -c in scripts-lint: a flag added to the installer fails the gate until it
# lands here and in the zsh file too
_install_sh_screen_shader() {
  local cur prev word
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"

  local flags=(
    -h --help -v --version --prefix --destdir --uninstall
    --extra-shader --rofi-prompt --waybar-signal
  )

  COMPREPLY=()
  case "$prev" in
    --prefix | --destdir)
      compopt -o dirnames 2>/dev/null || true
      return
      ;;
    --extra-shader)
      # A read loop, not mapfile: mapfile is bash 4.0
      while IFS= read -r word; do
        [[ -n "$word" ]] && COMPREPLY+=("$word")
      done < <(compgen -f -X '!*.frag' -- "$cur")
      compopt -o plusdirs 2>/dev/null || true
      return
      ;;
    --rofi-prompt | --waybar-signal)
      return
      ;;
  esac
  while IFS= read -r word; do
    [[ -n "$word" ]] && COMPREPLY+=("$word")
  done < <(compgen -W "${flags[*]}" -- "$cur")
}
complete -F _install_sh_screen_shader install.sh ./install.sh
