#!/bin/bash
# Claude Code raises no notification when it asks a question, so the popup for
# one cannot come from a hook. Poll the transcript instead and hand any pending
# question to notify-popup.sh, which already knows how to render and answer it.
INPUT=$(cat)

# Read the payload in the foreground, then hand it to a detached copy: polling
# from the hook itself would hold up SessionStart until the timeout.
if [ -z "$GHOSTTY_POPUP_WATCHER" ]; then
	export GHOSTTY_POPUP_WATCHER=1
	echo "$INPUT" | nohup "$0" >/dev/null 2>&1 &
	exit 0
fi

CWD=$(echo "$INPUT" | jq -r '.cwd')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')
SESSION=$(echo "$INPUT" | jq -r '.session_id')
HERE=$(cd "$(dirname "$0")" && pwd)
PIDFILE="$HOME/.claude/ghostty-input-popup.$SESSION.pid"
STALE_SECS=1800

[ -n "$TRANSCRIPT" ] && [ "$TRANSCRIPT" != null ] || exit 0

echo $$ >"$PIDFILE"

# A question's tool_use id changes per question, so it doubles as "have I shown
# this one yet" — including after a Dismiss, which should stay dismissed.
LAST=""
while :; do
	# SessionEnd removes the pidfile; a crashed session leaves the transcript
	# untouched. Either way, stop rather than linger as an orphan.
	[ -f "$PIDFILE" ] || exit 0
	if [ -e "$TRANSCRIPT" ]; then
		AGE=$(($(date +%s) - $(stat -f %m "$TRANSCRIPT")))
		[ "$AGE" -gt "$STALE_SECS" ] && exit 0
	fi

	SIG=$(tail -n 80 "$TRANSCRIPT" 2>/dev/null \
		| jq -s -r -f "$HERE/pending-question.jq" 2>/dev/null | jq -r '.qid' 2>/dev/null)

	if [ -n "$SIG" ] && [ "$SIG" != "$LAST" ]; then
		LAST=$SIG
		# Blocks until the picker is answered or dismissed, which is what keeps
		# a second popup from stacking on the first.
		jq -nc --arg cwd "$CWD" --arg t "$TRANSCRIPT" \
			'{cwd: $cwd, transcript_path: $t, notification_type: "question_watch", message: ""}' \
			| "$HERE/notify-popup.sh"
	fi
	sleep 1
done
