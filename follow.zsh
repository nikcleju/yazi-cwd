#!/usr/bin/env zsh
# Runs separately; only the interactive shell may actually change its cwd.
emulate -LR zsh
setopt no_monitor
# Process substitution does not expose a useful $! in Zsh.
print -r -- "$$"
local target=$1
local query="${0:A:h}/getcwd.zsh"
local listener_pid line kind rest sender body tab last_tab=''

coproc exec ya sub 'cd,hover'
listener_pid=$!
trap 'kill "$listener_pid" 2>/dev/null; wait "$listener_pid" 2>/dev/null' EXIT
trap 'exit 0' HUP INT TERM

_yazi_report_cwd() {
  local dir
  dir=$(zsh "$query" "$target" 2>/dev/null) || return 0
  jq -cn --arg cwd "$dir" '{cwd: $cwd}'
}

_yazi_report_cwd
while IFS= read -r -p line; do
  kind=${line%%,*}
  rest=${line#*,}
  rest=${rest#*,}
  sender=${rest%%,*}
  body=${rest#*,}
  [[ $sender == $target ]] || continue
  [[ $kind == cd || $kind == hover ]] || continue
  tab=$(print -r -- "$body" | jq -er '.tab | select(type == "number")') || continue
  # Hover events detect tab switches, but normal cursor movement needs no query.
  if [[ $kind == cd || $tab != $last_tab ]]; then
    last_tab=$tab
    _yazi_report_cwd
  fi
done
