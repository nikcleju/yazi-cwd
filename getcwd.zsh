#!/usr/bin/env zsh

emulate -LR zsh

if (( $# != 1 )) || [[ $1 != <-> ]] || (( $1 <= 0 )); then
	print -u2 'Usage: zsh getcwd.zsh <yazi-instance-id>'
	exit 2
fi

for dependency in ya jq; do
	if ! (( $+commands[$dependency] )); then
		print -u2 "Missing dependency: $dependency"
		exit 1
	fi
done

target_id=$1
marker="getcwd-client-$$-$RANDOM"
coproc exec ya sub "hey,return-active-cwd,$marker"
listener_pid=$!
trap 'exit_code=$?; kill "$listener_pid" 2>/dev/null; wait "$listener_pid" 2>/dev/null; exit "$exit_code"' EXIT

integer deadline=$(( SECONDS + 5 ))
client_id=''
while (( SECONDS < deadline )) && IFS= read -r -t $(( deadline - SECONDS )) -p line; do
	kind=${line%%,*}
	body=${line#*,}
	body=${body#*,}
	body=${body#*,}

	if [[ $kind == hey && -z $client_id ]]; then
		client_id=$(print -r -- "$body" | jq -r --arg marker "$marker" '
			.peers | to_entries[]
			| select(.value.abilities | index($marker)) | .key
		') || exit 1
		if [[ -n $client_id ]]; then
			request=$(jq -cn --argjson client_id "$client_id" '{client_id: $client_id}') || exit 1
			ya pub-to "$target_id" get-active-cwd --json "$request" || exit 1
		fi
	elif [[ $kind == return-active-cwd && -n $client_id ]]; then
		rest=${line#*,}
		receiver=${rest%%,*}
		rest=${rest#*,}
		sender=${rest%%,*}
		if [[ $receiver == $client_id && $sender == $target_id ]]; then
			print -r -- "$body" | jq -er '.cwd | select(type == "string")'
			exit $?
		fi
	fi
done

print -u2 'No cwd reply received within 5 seconds.'
exit 1
