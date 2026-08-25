#!/bin/bash
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')
PROJECT=$(basename "$CWD")
TERMINAL_APP=Ghostty

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
                   qtext: (.input.questions[0].question // ""),
                   choices: ([.input.questions[0].options[]?.label] | to_entries
                             | map("\(.key + 1). \(.value)")),
                   body: ([.input.questions[]?
                           | .question + "\n"
                             + ([.options[]?.label] | to_entries
                                | map("  \(.key + 1). \(.value)") | join("\n"))]
                          | join("\n\n") | .[0:700])}
             end')
KIND=$(jq -r '.kind' <<<"$DATA")
NQ=$(jq -r '.nq' <<<"$DATA")
BODY=$(jq -r '.body' <<<"$DATA")

# A single number can only ever answer the first question, so offer the picker
# only when there is exactly one. Anything else falls back to a plain notice.
if [ "$KIND" = question ] && [ "$NQ" = 1 ]; then
	PICK=$(osascript - "$PROJECT" "$(jq -r '.qtext' <<<"$DATA")" "$(jq -r '.choices[]' <<<"$DATA")" <<'APPLESCRIPT'
on run argv
	set choice to (choose from list (paragraphs of (item 3 of argv)) with title "Claude Code" with prompt ("Session: " & (item 1 of argv) & return & return & (item 2 of argv)) OK button name "Send" cancel button name "Dismiss")
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

	# Drive the waiting prompt by arrow key rather than a digit shortcut: moving
	# down IDX-1 times from the first option lands on the pick either way.
	osascript <<APPLESCRIPT
tell application "$TERMINAL_APP" to activate
delay 0.4
tell application "System Events"
	repeat $((IDX - 1)) times
		key code 125
	end repeat
	key code 36
end tell
APPLESCRIPT
else
	# Pass the text in as arguments so AppleScript needs no quote/backslash escaping
	osascript - "$PROJECT" "$BODY" <<'APPLESCRIPT'
on run argv
	display dialog "Session: " & (item 1 of argv) & return & return & (item 2 of argv) with title "Claude Code" buttons {"OK"} default button "OK"
end run
APPLESCRIPT
fi
