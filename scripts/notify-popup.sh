#!/bin/bash
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')
PROJECT=$(basename "$CWD")
TERMINAL_APP=Ghostty
LOG="$HOME/.claude/ghostty-input-popup.log"
NTYPE=$(echo "$INPUT" | jq -r '.notification_type // ""')
NMSG=$(echo "$INPUT" | jq -r '.message // ""')

# Pull whatever the session is actually waiting on: the last assistant block,
# be it prose or an AskUserQuestion. The question lives in a tool_use block, so
# matching text alone would show the prose above it instead of the question.
# Slice inside jq so the 700-char cap lands on a character boundary, not
# mid-UTF-8-sequence.
# -s is required: the transcript is JSONL, so without slurping jq would run the
# filter per line and `.[]` would iterate each record's values instead of the
# records themselves.
DATA=$(tail -n 50 "$TRANSCRIPT" 2>/dev/null \
  | jq -s -c '[.[] | select(.type=="assistant") | .message.content[]?
            | select(.type=="text" or (.type=="tool_use" and .name=="AskUserQuestion"))]
           | last
           | if . == null then {kind: "text", body: "Waiting for your input.", nq: 0}
             elif .type=="text" then {kind: "text", body: (.text[0:700]), nq: 0}
             else {kind: "question",
                   qid: .id,
                   nq: ([.input.questions[]?] | length),
                   questions: [.input.questions[]?
                               | {qtext: .question,
                                  choices: ([.options[]?.label] | to_entries
                                            | map("\(.key + 1). \(.value)"))}],
                   body: ([.input.questions[]?
                           | .question + "\n"
                             + ([.options[]?.label] | to_entries
                                | map("  \(.key + 1). \(.value)") | join("\n"))]
                          | join("\n\n") | .[0:700])}
             end')
KIND=$(jq -r '.kind' <<<"$DATA")
NQ=$(jq -r '.nq' <<<"$DATA")
BODY=$(jq -r '.body' <<<"$DATA")

# The popup can only ever show what the transcript held at fire time, so log
# that rather than guessing why the wrong message appeared.
jq -nc --arg ts "$(date -u +%FT%TZ)" --arg ev "$NMSG" --arg ntype "$NTYPE" \
       --arg kind "$KIND" --arg nq "$NQ" --arg peek "${BODY:0:80}" \
       '{ts: $ts, ntype: $ntype, event: $ev, kind: $kind, nq: $nq, peek: $peek}' >>"$LOG" 2>/dev/null

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

# Free text goes via the clipboard, not `keystroke`, which mangles Korean and
# emoji. Restore the old clipboard so answering a popup does not eat whatever
# the user had copied.
paste_text() {
	osascript - "$1" <<-APPLESCRIPT
		on run argv
			set saved to ""
			try
				set saved to the clipboard
			end try
			set the clipboard to (item 1 of argv)
			tell application "$TERMINAL_APP" to activate
			delay 0.4
			tell application "System Events"
				keystroke "v" using command down
				delay 0.2
				key code 36
			end tell
			delay 0.2
			try
				set the clipboard to saved
			end try
		end run
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

# The id of the question the transcript is waiting on, empty if it is not
# waiting on one. A dialog stays open after the question behind it is answered,
# so this is what tells a live pick from a stale one.
pending_qid() {
	tail -n 50 "$TRANSCRIPT" 2>/dev/null \
		| jq -s -r '[.[] | select(.type=="assistant") | .message.content[]?
		             | select(.type=="text" or (.type=="tool_use" and .name=="AskUserQuestion"))]
		            | last | if .type == "tool_use" then .id else "" end' 2>/dev/null
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
	[ "$(pending_qid)" = "$(jq -r '.qid' <<<"$DATA")" ] || exit 0
	send_keys "$REPLAY"
elif [ "$NTYPE" = idle_prompt ] && [ "$SESSIONS" -gt 1 ]; then
	# Nothing to say here that is worth a dialog: the session is merely idle, and
	# the reply cannot be sent from the popup anyway.
	exit 0
elif [ "$NTYPE" = idle_prompt ]; then
	# The terminal is sitting on a free prompt, so a typed reply can go straight
	# in. Prompt with the notification's own message: the transcript tail here is
	# the reply just given, which is what made these popups read as stale.
	REPLY=$(osascript - "$PROJECT" "$NMSG" <<'APPLESCRIPT'
on run argv
	set r to display dialog ("Session: " & (item 1 of argv) & return & return & (item 2 of argv)) with title "Claude Code" default answer "" buttons {"Dismiss", "Send"} default button "Send" giving up after 120
	if gave up of r then return ""
	if button returned of r is "Dismiss" then return ""
	return text returned of r
end run
APPLESCRIPT
)
	# Not `[ -n ... ] && paste_text`: as the last command in the branch that
	# would exit 1 on Dismiss, reporting a hook failure for a normal cancel.
	if [ -n "$REPLY" ]; then
		paste_text "$REPLY"
	fi
elif [ "$NTYPE" = permission_prompt ]; then
	# A permission decision blocks the session just as a question does. Show the
	# notification's own message, never the transcript tail, which at this point
	# is the prose leading up to the tool call.
	notice "$NMSG"
else
	# Nothing is blocking, so nothing is worth interrupting for. Popping up on
	# idle showed whatever message the transcript happened to end on, which
	# reads as a reply rather than something to answer.
	exit 0
fi
