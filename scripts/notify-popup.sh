#!/bin/bash
INPUT=$(cat)
CWD=$(echo "$INPUT" | jq -r '.cwd')
TRANSCRIPT=$(echo "$INPUT" | jq -r '.transcript_path')
PROJECT=$(basename "$CWD")

# Pull whatever the session is actually waiting on: the last assistant block,
# be it prose or an AskUserQuestion. The question lives in a tool_use block, so
# matching text alone would show the prose above it instead of the question.
# Slice inside jq so the 300-char cap lands on a character boundary, not
# mid-UTF-8-sequence.
MSG=$(tail -n 50 "$TRANSCRIPT" 2>/dev/null \
  | jq -rs '[.[] | select(.type=="assistant") | .message.content[]?
             | select(.type=="text" or (.type=="tool_use" and .name=="AskUserQuestion"))]
            | last
            | if . == null then "Waiting for your input."
              elif .type=="text" then .text
              else [.input.questions[]?.question] | join("\n\n")
              end
            | .[0:300]')

# Pass the text in as arguments so AppleScript needs no quote/backslash escaping
osascript - "$PROJECT" "$MSG" <<'APPLESCRIPT'
on run argv
	display dialog "Session: " & (item 1 of argv) & return & return & (item 2 of argv) with title "Claude Code" buttons {"OK"} default button "OK"
end run
APPLESCRIPT
