#!/usr/bin/env zsh
# Discover compatible Yazi instances and query them concurrently over DDS.
emulate -LR zsh

for dependency in ya jq; do
  if ! (( $+commands[$dependency] )); then
    print -u2 "Missing dependency: $dependency"
    exit 1
  fi
done

local marker="yazi-cwd-discover-$$-$RANDOM"
local listener_pid client_id='' line kind rest receiver sender body request id result
local -a candidates
local -A pending
integer deadline=$(( SECONDS + 5 ))

coproc exec ya sub "hey,return-active-cwd,$marker"
listener_pid=$!
trap 'kill "$listener_pid" 2>/dev/null; wait "$listener_pid" 2>/dev/null' EXIT
trap 'exit 1' HUP INT TERM

while (( SECONDS < deadline )) && IFS= read -r -t $(( deadline - SECONDS )) -p line; do
  kind=${line%%,*}
  rest=${line#*,}
  receiver=${rest%%,*}
  rest=${rest#*,}
  sender=${rest%%,*}
  body=${rest#*,}

  if [[ $kind == hey && -z $client_id ]]; then
    client_id=$(print -r -- "$body" | jq -r --arg marker "$marker" '
      .peers | to_entries[]
      | select(.value.abilities | index($marker)) | .key
    ') || exit 1
    [[ $client_id == <-> ]] && (( client_id > 0 )) || continue
    candidates=("${(@f)$(print -r -- "$body" | jq -r '
      .peers | to_entries[]
      | select(.value.abilities | index("get-active-cwd")) | .key
    ')}")
    request=$(jq -cn --argjson client_id "$client_id" '{client_id: $client_id}') || exit 1
    for id in "${candidates[@]}"; do
      [[ $id == <-> ]] && (( id > 0 )) || continue
      if ya pub-to "$id" get-active-cwd --json "$request"; then
        pending[$id]=1
      fi
    done
    (( ${#pending} )) || exit 0
  elif [[ $kind == return-active-cwd && -n $client_id && $receiver == $client_id && -n ${pending[$sender]} ]]; then
    result=$(print -r -- "$body" | jq -ce --arg id "$sender" '
      .cwd | select(type == "string") | {id: $id, cwd: .}
    ') || continue
    print -r -- "$result"
    unset "pending[$sender]"
    (( ${#pending} )) || exit 0
  fi
done
# Partial results are useful when one of the discovered peers has exited.
exit 0
