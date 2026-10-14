# Pair this shell with a running Yazi using yazi-connect.
# A Yazi subshell can use its inherited YAZI_ID without explicit pairing.
typeset -g _yazi_cwd_query="${${(%):-%x}:A:h}/getcwd.zsh"

_yazi_follow_cwd() {
  emulate -L zsh
  [[ ${_yazi_cwd_pulling-} == 1 ]] && return 0
  local target=${YAZI_CWD_ID:-${YAZI_ID-}}
  [[ $target == <-> ]] && (( target > 0 )) || return 0
  command ya emit-to "$target" cd "$PWD"
  return 0
}

cdy() {
  emulate -L zsh
  local dir target=${1:-${YAZI_CWD_ID:-${YAZI_ID-}}}
  if [[ $target != <-> ]] || (( target <= 0 )); then
    print -u2 'Not connected to Yazi. Run yazi-connect first.'
    return 1
  fi
  # A sentinel preserves path newlines; remove only the helper's final newline.
  dir=$(zsh "$_yazi_cwd_query" "$target" && print -rn -- .) || return
  dir=${${dir%.}%$'\n'}
  local _yazi_cwd_pulling=1
  builtin cd -- "$dir"
}

# Discovery runs in a helper so its coprocess cannot replace a shell coprocess.
yazi-connect() {
  emulate -L zsh
  if (( $# )); then
    print -u2 'Usage: yazi-connect'
    return 2
  fi
  local snapshot row choice id dir
  local -a instances
  snapshot=$(zsh "${_yazi_cwd_query:h}/discover.zsh") || return
  if [[ -z $snapshot ]]; then
    print -u2 'No compatible Yazi instances found. Enable the getcwd plugin in Yazi.'
    return 1
  fi
  snapshot=$(print -r -- "$snapshot" | command jq -cs 'sort_by(.id | tonumber)[]') || return
  instances=("${(@f)snapshot}")
  if (( ${#instances} == 1 )); then
    choice=1
  else
    integer n=1
    for row in "${instances[@]}"; do
      # JSON-quote paths so unusual filenames cannot inject terminal controls.
      print -r -- "$n) $(print -r -- "$row" | command jq -r '"\(.cwd | @json) [ID \(.id)]"' 2>/dev/null)"
      (( n++ ))
    done
    read -r "choice?Connect to Yazi [1-${#instances}, Enter to cancel]: " || return 1
    [[ -n $choice ]] || return 0
    if [[ $choice != <-> ]] || (( choice < 1 || choice > ${#instances} )); then
      print -u2 'Invalid selection; connection unchanged.'
      return 1
    fi
  fi
  id=$(print -r -- "${instances[$choice]}" | command jq -r '.id') || return
  # Revalidate after the menu, before replacing a working connection.
  dir=$(zsh "$_yazi_cwd_query" "$id" && print -rn -- .) || return
  dir=${${dir%.}%$'\n'}
  if [[ $dir != /* || ! -d $dir ]]; then
    print -u2 'The selected Yazi directory is not an accessible local directory.'
    return 1
  fi
  local _yazi_cwd_pulling=1
  builtin cd -- "$dir" || return
  yazi-cwd-stop
  typeset -g YAZI_CWD_ID=$id
  yazi-cwd-start
  print -r -- "Connected to Yazi $id."
}

_cdy_widget() {
  emulate -L zsh
  cdy
  zle reset-prompt
}

# Close only resources created by this shell; also used before re-sourcing.
yazi-cwd-stop() {
  emulate -L zsh
  if [[ -n ${_yazi_cwd_fd-} ]]; then
    zle -F "$_yazi_cwd_fd" 2>/dev/null
    exec {_yazi_cwd_fd}<&-
    unset _yazi_cwd_fd
  fi
  if [[ ${_yazi_cwd_pid-} == <-> ]] && (( _yazi_cwd_pid > 1 )); then
    kill "$_yazi_cwd_pid" 2>/dev/null
    wait "$_yazi_cwd_pid" 2>/dev/null
    unset _yazi_cwd_pid
  fi
  unset _yazi_cwd_target
  return 0
}

_yazi_cwd_receive() {
  emulate -L zsh
  local line latest dir
  if [[ -n ${2-} ]] || ! IFS= read -r -u "$1" line; then
    yazi-cwd-stop
    return 0
  fi
  latest=$line
  # If a command was running, apply only the latest queued directory.
  while IFS= read -r -t 0 -u "$1" line; do
    latest=$line
  done
  dir=$(print -r -- "$latest" | command jq -ej '.cwd | select(type == "string")' &&
    print -rn -- .) || return 0
  dir=${dir%.}
  [[ $dir == /* && -d $dir && $dir != $PWD ]] || return 0
  local _yazi_cwd_pulling=1
  builtin cd -- "$dir" || return 0
  zle reset-prompt
}

yazi-cwd-start() {
  emulate -L zsh
  local target=${YAZI_CWD_ID:-${YAZI_ID-}}
  [[ -o interactive && $target == <-> ]] && (( target > 0 )) || return 0
  (( $+commands[ya] && $+commands[jq] )) || return 0
  if [[ -n ${_yazi_cwd_fd-} && ${_yazi_cwd_target-} == $target ]]; then
    return 0
  fi
  yazi-cwd-stop
  typeset -g _yazi_cwd_fd _yazi_cwd_pid _yazi_cwd_target=$target
  exec {_yazi_cwd_fd}< <(exec zsh "${_yazi_cwd_query:h}/follow.zsh" "$target")
  if ! IFS= read -r -t 2 -u "$_yazi_cwd_fd" _yazi_cwd_pid ||
      [[ $_yazi_cwd_pid != <-> ]] || (( _yazi_cwd_pid <= 1 )); then
    unset _yazi_cwd_pid
    yazi-cwd-stop
    return 0
  fi
  zle -F "$_yazi_cwd_fd" _yazi_cwd_receive
}

autoload -Uz add-zsh-hook
add-zsh-hook chpwd _yazi_follow_cwd
add-zsh-hook precmd yazi-cwd-start
add-zsh-hook zshexit yazi-cwd-stop
zle -N _cdy_widget
bindkey '^G' _cdy_widget

# Re-sourcing replaces the old listener instead of leaking another process.
yazi-cwd-stop
[[ -o interactive ]] && yazi-cwd-start
