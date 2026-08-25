#!/bin/bash
# Shows the dialog for a question straight from the PreToolUse payload.
#
# Polling the transcript cannot see a pending question at all: Claude Code
# flushes the transcript at turn boundaries, so the record for the question and
# the record for its answer land in the same write. Measured on 2026-08-25 — the
# file sat untouched for the whole 12 seconds a question was on screen, then grew
# by six records at once. Every popup the watcher could ever fire is therefore
# either late or suppressed by the answered-check in pending-question.jq.
#
# The hook payload carries `tool_input.questions` outright, so nothing is read
# from disk and the question is in hand while it is still pending.
INPUT=$(cat)
LOG="$HOME/.claude/ghostty-input-popup.log"

PROJECT=$(basename "$(jq -r '.cwd' <<<"$INPUT")")
BODY=$(jq -r '[.tool_input.questions[]?
	| .question + "\n"
	  + ([.options[]?.label] | to_entries
	     | map("  \(.key + 1). \(.value)") | join("\n"))]
	| join("\n\n") | .[0:700]' <<<"$INPUT")

# Same shape the watcher's popup logs, so one log still answers "why did that
# appear" no matter which path fired.
jq -nc --arg ts "$(date -u +%FT%TZ)" --arg src hook \
       --arg qid "$(jq -r '.tool_use_id' <<<"$INPUT")" \
       --arg nq "$(jq -r '[.tool_input.questions[]?] | length' <<<"$INPUT")" \
       --arg peek "${BODY:0:80}" \
       '{ts: $ts, src: $src, kind: "question", nq: $nq, qid: $qid, peek: $peek}' \
	>>"$LOG" 2>/dev/null

# PreToolUse runs before the tool, so blocking here would hold the question off
# the terminal until the dialog closed. Detach it and get out of the way.
nohup osascript - "$PROJECT" "$BODY" >/dev/null 2>&1 <<'APPLESCRIPT' &
on run argv
	display dialog "Session: " & (item 1 of argv) & return & return & (item 2 of argv) with title "Claude Code" buttons {"OK"} default button "OK" giving up after 120
end run
APPLESCRIPT
exit 0
