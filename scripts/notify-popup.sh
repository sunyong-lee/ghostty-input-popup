#!/bin/bash
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')
PROJECT=$(basename "$CWD")
TERMINAL_APP=Ghostty
LOG="$HOME/.claude/ghostty-input-popup.log"

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
jq -nc --arg ts "$(date -u +%FT%TZ)" --arg ev "$(jq -r '.message // ""' <<<"$INPUT")" \
       --arg kind "$KIND" --arg nq "$NQ" --arg peek "${BODY:0:80}" \
       '{ts: $ts, event: $ev, kind: $kind, nq: $nq, peek: $peek}' >>"$LOG" 2>/dev/null

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

if [ "$KIND" = question ]; then
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
	send_keys "$REPLAY"
else
	# No pending question, so the terminal is sitting on a plain prompt and a
	# typed reply can go straight in. Pass the body as an argument so
	# AppleScript needs no quote/backslash escaping.
	REPLY=$(osascript - "$PROJECT" "$BODY" <<'APPLESCRIPT'
on run argv
	set r to display dialog ("Session: " & (item 1 of argv) & return & return & (item 2 of argv)) with title "Claude Code" default answer "" buttons {"Dismiss", "Send"} default button "Send"
	if button returned of r is "Dismiss" then return ""
	return text returned of r
end run
APPLESCRIPT
)
	[ -n "$REPLY" ] && paste_text "$REPLY"
fi
