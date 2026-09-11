# shellcheck shell=bash
# Tab completion for screen-shader in bash. Hand-written on purpose and drift-checked by
# machine: check-sh.sh -c, run by the flake's scripts-lint, holds every word here to the
# manager's dispatcher and parsers. Builtins only, so it works without the bash-completion
# package and under the bash 3.2 a stock macOS sources it with.

_screen_shader_names() {
  # Live names from the tool itself: menu prints "<emoji> <label>|<name>" lines
  screen-shader menu 2>/dev/null | cut -d'|' -f2
}

_screen_shader() {
  local cur prev words="" word
  cur="${COMP_WORDS[COMP_CWORD]}"
  prev="${COMP_WORDS[COMP_CWORD - 1]}"
  COMPREPLY=()
  if ((COMP_CWORD == 1)); then
    words="effect bright flash add remove rm restore reset-all status menu help -v --version"
  else
    case "${COMP_WORDS[1]}" in
      effect)
        if ((COMP_CWORD == 2)); then
          words="push set clear toggle next prev"
        else
          case "${COMP_WORDS[2]}" in
            push | set | toggle) words="$(_screen_shader_names)" ;;
          esac
        fi
        ;;
      bright)
        if ((COMP_CWORD == 2)); then
          words="up down reset toggle set get"
        fi
        ;;
      flash)
        if [[ "$cur" == -* ]]; then
          words="-k --keep"
        else
          words="$(_screen_shader_names)"
        fi
        ;;
      remove | rm) words="$(_screen_shader_names)" ;;
      add)
        case "$prev" in
          --name | --label | --emoji | --order) return ;;
        esac
        if [[ "$cur" == -* ]]; then
          words="--name --label --emoji --order --animated --samples --raw"
          words+=" --no-animated --no-samples --no-raw -f --force"
        else
          # Effect sources only; directories still complete so a path can be walked. A
          # read loop, not mapfile: mapfile is bash 4.0
          while IFS= read -r word; do
            [[ -n "$word" ]] && COMPREPLY+=("$word")
          done < <(compgen -f -X '!*.frag' -- "$cur")
          compopt -o plusdirs 2>/dev/null || true
          return
        fi
        ;;
    esac
  fi
  while IFS= read -r word; do
    [[ -n "$word" ]] && COMPREPLY+=("$word")
  done < <(compgen -W "$words" -- "$cur")
}

complete -F _screen_shader screen-shader
