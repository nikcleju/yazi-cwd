# Match the ID used when starting Yazi: yazi --client-id 123456.
# An explicitly configured ID or a Yazi subshell's YAZI_ID takes precedence.
export YAZI_CWD_ID=${YAZI_CWD_ID:-123456}
typeset -g _yazi_cwd_query="${${(%):-%x}:A:h}/getcwd.zsh"

_yazi_follow_cwd() {
  [[ $_yazi_cwd_pulling == 1 ]] && return 0
  local target=${YAZI_ID:-$YAZI_CWD_ID}
  [[ $target == <-> ]] && (( target > 0 )) || return 0
  command ya emit-to "$target" cd "$PWD"
  return 0
}

cdy() {
  local dir
  dir=$(zsh "$_yazi_cwd_query" "${1:-${YAZI_ID:-$YAZI_CWD_ID}}") || return
  local _yazi_cwd_pulling=1
  builtin cd -- "$dir"
}

_cdy_widget() {
  cdy
  zle reset-prompt
}

# Close only resources created by this shell; also used before re-sourcing.
yazi-cwd-stop() {
  if [[ -n $_yazi_cwd_fd ]]; then
    zle -F "$_yazi_cwd_fd" 2>/dev/null
    exec {_yazi_cwd_fd}<&-
    unset _yazi_cwd_fd
  fi
  if [[ $_yazi_cwd_pid == <-> ]] && (( _yazi_cwd_pid > 1 )); then
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
  if [[ -n $2 ]] || ! IFS= read -r -u "$1" line; then
    yazi-cwd-stop
    return 0
  fi
  latest=$line
  # If a command was running, apply only the latest queued directory.
  while IFS= read -r -t 0 -u "$1" line; do
    latest=$line
  done
  dir=$(print -r -- "$latest" | command jq -er '.cwd | select(type == "string")') || return 0
  [[ $dir == /* && -d $dir && $dir != $PWD ]] || return 0
  local _yazi_cwd_pulling=1
  builtin cd -- "$dir" || return 0
  zle reset-prompt
}

yazi-cwd-start() {
  emulate -L zsh
  local target=${YAZI_ID:-$YAZI_CWD_ID}
  [[ -o interactive && $target == <-> ]] && (( target > 0 )) || return 0
  (( $+commands[ya] && $+commands[jq] )) || return 0
  if [[ -n $_yazi_cwd_fd && $_yazi_cwd_target == $target ]]; then
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
