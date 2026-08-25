#!/bin/bash
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')
PROJECT=$(basename "$CWD")
LOG="$HOME/.claude/ghostty-input-popup.log"
HERE=$(cd "$(dirname "$0")" && pwd)

# -s is required: the transcript is JSONL, so without slurping the filter would
# run per line and see each record's values instead of the records themselves.
DATA=$(tail -n 80 "$TRANSCRIPT" 2>/dev/null | jq -s -c -f "$HERE/pending-question.jq" 2>/dev/null)
KIND=$(jq -r '.kind' <<<"$DATA")
NQ=$(jq -r '.nq' <<<"$DATA")
BODY=$(jq -r '.body' <<<"$DATA")
QID=$(jq -r '.qid' <<<"$DATA")

# The popup can only ever show what the transcript held at fire time, so log
# that rather than guessing why the wrong message appeared.
jq -nc --arg ts "$(date -u +%FT%TZ)" --arg kind "$KIND" --arg nq "$NQ" \
       --arg qid "$QID" --arg peek "${BODY:0:80}" \
       '{ts: $ts, kind: $kind, nq: $nq, qid: $qid, peek: $peek}' >>"$LOG" 2>/dev/null

# A question is the only thing worth interrupting for. Idle and permission
# popups both showed up with nothing to answer, which is just noise.
[ "$KIND" = question ] || exit 0

# Report the question and let the terminal answer it. Replaying keys was tried
# and dropped: they go to whichever window is frontmost once the terminal is
# activated, and AppleScript cannot pick out a terminal's tab, so answers landed
# in a different session. Give up after a while rather than outlive the question
# and stack up behind the next one.
osascript - "$PROJECT" "$BODY" <<'APPLESCRIPT'
on run argv
	display dialog "Session: " & (item 1 of argv) & return & return & (item 2 of argv) with title "Claude Code" buttons {"OK"} default button "OK" giving up after 120
end run
APPLESCRIPT
