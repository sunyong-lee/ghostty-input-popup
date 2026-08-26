#!/bin/bash
# Shows the question from the PreToolUse payload and takes the answer.
#
# Polling the transcript cannot see a pending question at all: Claude Code
# flushes the transcript at turn boundaries, so the record for the question and
# the record for its answer land in the same write. Measured on 2026-08-25 — the
# file sat untouched for the whole 12 seconds a question was on screen, then grew
# by six records at once. The hook payload carries `tool_input.questions`
# outright, so the question is in hand while it is still pending.
#
# Answering used to mean activating the terminal and replaying keys into it,
# which landed answers in the wrong session because AppleScript cannot address a
# particular window or tab. The hook needs none of that: a pick travels back as
# the reason on a denied tool call. Claude cannot be handed a tool result by a
# PreToolUse hook, so denying with the pick as the reason is the only channel
# there is.
INPUT=$(cat)
LOG="$HOME/.claude/ghostty-input-popup.log"
GIVE_UP=120
ESCAPE="(answer in the terminal instead)"

PROJECT=$(basename "$(jq -r '.cwd' <<<"$INPUT")")
NQ=$(jq -r '[.tool_input.questions[]?] | length' <<<"$INPUT")
QID=$(jq -r '.tool_use_id' <<<"$INPUT")

# Logged before the dialog opens, so a popup that surprises you is traceable
# even if this run never gets to deliver an answer.
jq -nc --arg ts "$(date -u +%FT%TZ)" --arg qid "$QID" --arg nq "$NQ" \
       --arg peek "$(jq -r '.tool_input.questions[0].question // ""' <<<"$INPUT" | cut -c1-80)" \
       '{ts: $ts, src: "hook", kind: "question", nq: $nq, qid: $qid, peek: $peek}' \
	>>"$LOG" 2>/dev/null

[ "$NQ" -gt 0 ] 2>/dev/null || exit 0

# `choose from list` has no `giving up after`, so the wait is bounded out here.
# Prints the picked label, or fails if the dialog was cancelled or ran out.
ask_one() {
	local prompt=$1 tmp pid waited=0 out
	shift
	tmp=$(mktemp) || return 1
	osascript - "$prompt" "$@" >"$tmp" 2>/dev/null <<'APPLESCRIPT' &
on run argv
	set opts to {}
	repeat with i from 2 to (count of argv)
		set end of opts to item i of argv
	end repeat
	set picked to choose from list opts with title "Claude Code" with prompt (item 1 of argv) default items {item 1 of opts}
	if picked is false then
		return "__NONE__"
	end if
	return item 1 of picked
end run
APPLESCRIPT
	pid=$!
	while kill -0 "$pid" 2>/dev/null; do
		if [ "$waited" -ge "$GIVE_UP" ]; then
			kill "$pid" 2>/dev/null
			rm -f "$tmp"
			return 1
		fi
		sleep 1
		waited=$((waited + 1))
	done
	out=$(cat "$tmp")
	rm -f "$tmp"
	if [ -z "$out" ] || [ "$out" = "__NONE__" ] || [ "$out" = "$ESCAPE" ]; then
		return 1
	fi
	printf '%s' "$out"
}

# One abandoned question abandons the lot: half an answer is worse for Claude
# than none, and the terminal picker still has every question.
ANSWERS=""
i=0
while [ "$i" -lt "$NQ" ]; do
	Q=$(jq -r --argjson i "$i" '.tool_input.questions[$i].question' <<<"$INPUT")
	OPTS=$(jq -r --argjson i "$i" '.tool_input.questions[$i].options[]?.label' <<<"$INPUT")
	# Labels are one per line and may contain spaces, so split on newlines only,
	# with globbing off so a label like `*` stays itself.
	set -f
	OLDIFS=$IFS
	IFS=$'\n'
	set -- $OPTS
	IFS=$OLDIFS
	set +f
	PICK=$(ask_one "$PROJECT — $Q" "$@" "$ESCAPE") || exit 0
	ANSWERS="$ANSWERS
$Q -> $PICK"
	i=$((i + 1))
done

jq -nc --arg ts "$(date -u +%FT%TZ)" --arg qid "$QID" \
       --arg peek "$(printf '%s' "$ANSWERS" | tr '\n' ' ' | sed 's/^ *//' | cut -c1-80)" \
       '{ts: $ts, src: "hook", kind: "answer", qid: $qid, peek: $peek}' \
	>>"$LOG" 2>/dev/null

jq -n --arg a "$ANSWERS" '{
	hookSpecificOutput: {
		hookEventName: "PreToolUse",
		permissionDecision: "deny",
		permissionDecisionReason: ("The user answered in the popup, so the question is settled — do not ask it again:" + $a)
	}
}'
exit 0
