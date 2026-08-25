#!/bin/bash
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')
PROJECT=$(basename "$CWD")
TERMINAL_APP=Ghostty
LOG="$HOME/.claude/ghostty-input-popup.log"
HERE=$(cd "$(dirname "$0")" && pwd)

# -s is required: the transcript is JSONL, so without slurping the filter would
# run per line and see each record's values instead of the records themselves.
read_pending() {
	tail -n 80 "$TRANSCRIPT" 2>/dev/null | jq -s -c -f "$HERE/pending-question.jq" 2>/dev/null
}

DATA=$(read_pending)
KIND=$(jq -r '.kind' <<<"$DATA")
NQ=$(jq -r '.nq' <<<"$DATA")
BODY=$(jq -r '.body' <<<"$DATA")
QID=$(jq -r '.qid' <<<"$DATA")

# The popup can only ever show what the transcript held at fire time, so log
# that rather than guessing why the wrong message appeared.
jq -nc --arg ts "$(date -u +%FT%TZ)" --arg kind "$KIND" --arg nq "$NQ" \
       --arg qid "$QID" --arg peek "${BODY:0:80}" \
       '{ts: $ts, kind: $kind, nq: $nq, qid: $qid, peek: $peek}' >>"$LOG" 2>/dev/null

# Replay the collected answers in one go. Arrow keys rather than digit
# shortcuts: moving down IDX-1 times from the first option lands on the pick
# either way.
send_keys() {
	osascript <<-APPLESCRIPT
		tell application "$TERMINAL_APP" to activate
		delay 0.4
		tell application "System Events"
		$1
		end tell
	APPLESCRIPT
}

# Give up rather than sit there: an unread notice outlives what it was reporting
# and then stacks up behind the next one.
notice() {
	osascript - "$PROJECT" "$1" <<'APPLESCRIPT'
on run argv
	display dialog "Session: " & (item 1 of argv) & return & return & (item 2 of argv) with title "Claude Code" buttons {"OK"} default button "OK" giving up after 30
end run
APPLESCRIPT
}

# A dialog stays open after the question behind it is answered, so re-read
# rather than trust what was pending when it opened.
pending_qid() {
	jq -r '.qid' <<<"$(read_pending)"
}

# Keys go to whichever window is frontmost once the terminal is activated, so
# with more than one session running an answer lands in the wrong one. Each
# watcher leaves a pidfile, so counting them says when sending is unsafe.
SESSIONS=$(find "$HOME/.claude" -maxdepth 1 -name 'ghostty-input-popup.*.pid' 2>/dev/null | wc -l | tr -d ' ')

if [ "$KIND" = question ] && [ "$SESSIONS" -gt 1 ]; then
	# Still say what is waiting; just do not pretend it can be answered here.
	notice "$BODY"
elif [ "$KIND" = question ]; then
	# Collect every pick before sending a single key. Answering as you go would
	# leave the session half-filled the moment you hit Dismiss on question 2.
	REPLAY=""
	for ((i = 0; i < NQ; i++)); do
		PICK=$(osascript - "$PROJECT" "$(jq -r ".questions[$i].qtext" <<<"$DATA")" \
			"$(jq -r ".questions[$i].choices[]" <<<"$DATA")" "Question $((i + 1)) of $NQ" <<'APPLESCRIPT'
on run argv
	set choice to (choose from list (paragraphs of (item 3 of argv)) with title "Claude Code" with prompt ("Session: " & (item 1 of argv) & "  —  " & (item 4 of argv) & return & return & (item 2 of argv)) OK button name "Send" cancel button name "Dismiss")
	if choice is false then return ""
	return item 1 of choice
end run
APPLESCRIPT
)
		# Labels are prefixed "N. ", so the leading digits are the 1-based choice
		IDX=${PICK%%.*}
		case $IDX in
		'' | *[!0-9]*) exit 0 ;;
		esac
		REPLAY="$REPLAY
	repeat $((IDX - 1)) times
		key code 125
	end repeat
	key code 36
	delay 0.35"
	done
	# Answering in the terminal leaves this dialog open, so by now the picks may
	# belong to a question that is already settled. Sending them would answer
	# whatever the session moved on to.
	[ "$(pending_qid)" = "$QID" ] || exit 0
	send_keys "$REPLAY"
else
	# A question is the only thing worth interrupting for. Idle and permission
	# popups both showed up with nothing to answer, which is just noise.
	exit 0
fi
