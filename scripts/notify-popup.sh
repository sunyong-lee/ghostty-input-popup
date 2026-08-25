#!/bin/bash
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')
PROJECT=$(basename "$CWD")

# Pull the last assistant text message from the transcript
MSG=$(tail -n 50 "$TRANSCRIPT" 2>/dev/null \
  | jq -rs '[.[] | select(.type=="assistant") | .message.content[]? | select(.type=="text") | .text] | last // "Waiting for your input."' \
  | head -c 300)

# Escape backslashes and double quotes for AppleScript
SAFE_MSG=$(printf '%s' "$MSG" | sed 's/\\/\\\\/g; s/"/\\"/g')

osascript <<APPLESCRIPT
display dialog "Session: $PROJECT

$SAFE_MSG" with title "Claude Code" buttons {"OK"} default button "OK"
APPLESCRIPT
