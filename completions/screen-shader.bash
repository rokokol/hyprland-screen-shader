# shellcheck shell=bash
# bash completion for screen-shader. The command lists are spelled here by hand;
# tests/run.sh checks them against the dispatcher's usage line, so a command added there
# fails the suite until it lands here
_screen_shader_names() {
  # Live names from the tool itself: menu prints "<emoji> <label>|<name>" lines
  screen-shader menu 2>/dev/null | cut -d'|' -f2
}

_screen_shader() {
  local cur=${COMP_WORDS[COMP_CWORD]}
  local cmd=${COMP_WORDS[1]-} sub=${COMP_WORDS[2]-}

  if ((COMP_CWORD == 1)); then
    mapfile -t COMPREPLY < <(compgen -W "effect bright flash add remove restore reset-all status menu help --version" -- "$cur")
    return
  fi

  case "$cmd" in
    effect)
      if ((COMP_CWORD == 2)); then
        mapfile -t COMPREPLY < <(compgen -W "push set clear toggle next prev" -- "$cur")
      elif [[ $sub == push || $sub == set || $sub == toggle ]]; then
        mapfile -t COMPREPLY < <(compgen -W "$(_screen_shader_names)" -- "$cur")
      fi
      ;;
    bright)
      if ((COMP_CWORD == 2)); then
        mapfile -t COMPREPLY < <(compgen -W "up down reset toggle set get" -- "$cur")
      fi
      ;;
    flash | remove)
      mapfile -t COMPREPLY < <(compgen -W "$(_screen_shader_names)" -- "$cur")
      ;;
    add)
      if ((COMP_CWORD == 2)); then
        # Effect sources only; directories still complete so a path can be walked
        mapfile -t COMPREPLY < <(compgen -f -X '!*.frag' -- "$cur")
        compopt -o plusdirs 2>/dev/null || true
      fi
      ;;
  esac
}

complete -F _screen_shader screen-shader
