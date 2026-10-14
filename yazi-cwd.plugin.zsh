 # Match the ID used when starting Yazi: yazi --client-id 123456
 export YAZI_CWD_ID=123456

# Get the path to the getcwd.zsh script
typeset -g _yazi_cwd_query="${${(%):-%x}:A:h}/getcwd.zsh"

# Hook called when the current working directory changes.
_yazi_follow_cwd() {
  # Don't send changes originating from cdy back to Yazi.
  [[ $_yazi_cwd_pulling == 1 ]] && return 0

  local target=${YAZI_ID:-$YAZI_CWD_ID}
  [[ -n $target ]] || return 0

  command ya emit-to "$target" cd "$PWD"
  return 0
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _yazi_follow_cwd

# Change to Yazi's current working directory.
cdy() {
  local dir
  dir=$(zsh "$_yazi_cwd_query" \
    "${1:-${YAZI_ID:-$YAZI_CWD_ID}}") || return

  local _yazi_cwd_pulling=1
  builtin cd -- "$dir"
}

# Ctrl-G: change to Yazi's current directory and refresh the prompt.
_cdy_widget() {
  cdy
  zle reset-prompt
}

# Bind the widget to Ctrl-G.
zle -N _cdy_widget
bindkey '^G' _cdy_widget

