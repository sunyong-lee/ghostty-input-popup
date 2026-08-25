#!/bin/bash
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')
PROJECT=$(basename "$CWD")

# Pull the last assistant text message from the transcript. Slice inside jq so
# the 300-char cap lands on a character boundary, not mid-UTF-8-sequence.
MSG=$(tail -n 50 "$TRANSCRIPT" 2>/dev/null \
  | jq -rs '([.[] | select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text] | last // "Waiting for your input.")[0:300]')

# Pass the text in as arguments so AppleScript needs no quote/backslash escaping
osascript - "$PROJECT" "$MSG" <<'APPLESCRIPT'
on run argv
	display dialog "Session: " & (item 1 of argv) & return & return & (item 2 of argv) with title "Claude Code" buttons {"OK"} default button "OK"
end run
APPLESCRIPT
