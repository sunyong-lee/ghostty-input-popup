#!/bin/bash
# Removing the pidfile is what actually stops the watcher; the kill just saves
# it the last second of sleep.
INPUT=$(cat)
SESSION=$(echo "$INPUT" | jq -r '.session_id')
PIDFILE="$HOME/.claude/ghostty-input-popup.$SESSION.pid"

[ -f "$PIDFILE" ] || exit 0
PID=$(cat "$PIDFILE")
rm -f "$PIDFILE"
[ -n "$PID" ] && kill "$PID" 2>/dev/null
exit 0
