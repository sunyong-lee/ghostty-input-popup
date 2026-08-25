# ghostty-input-popup

A Claude Code plugin that pops up a macOS dialog when a session asks you a
question — and lets you answer from the dialog, so you never lose track of which
of your concurrent sessions is waiting.

Questions only. Nothing pops up while a session is merely idle or waiting on a
permission decision: a dialog with nothing to answer is noise.

## Install

```
/plugin marketplace add sunyong-lee/ghostty-input-popup
/plugin install ghostty-input-popup@personal-plugins
```

## What you get

| Sessions running | Popup |
|---|---|
| one | a list of the question's options — pick one and it is sent for you |
| several | the question and its options, to answer in the terminal |

Every pick is collected before anything is sent, so Dismiss at any point sends
nothing at all. Picks reach the session as arrow keys after the terminal is
activated, which is why more than one session means no sending: the keys go to
whichever window is frontmost, not necessarily the one that asked.

## How it works

Claude Code raises no notification when it asks a question, so a hook cannot see
one. A `SessionStart` hook detaches `scripts/watch-questions.sh`, which reads the
transcript once a second and hands any pending question to
`scripts/notify-popup.sh`. `SessionEnd` removes the pidfile the watcher checks
each second; a session that dies without it gives up on a transcript left
untouched for 30 minutes.

Whether a question is still pending is decided by
`scripts/pending-question.jq`, shared so the watcher and the popup cannot
disagree. An answer is recorded as a user `tool_result`, not an assistant block,
so a filter that reads only assistant blocks calls an answered question pending —
which made popups appear just after answering. The pick is checked against that
filter again before any key is sent, because a dialog outlives the question
behind it.

`~/.claude/ghostty-input-popup.log` gets one line per run — what was pending, the
question id, first 80 characters. Start there when a popup surprises you.

## Requirements

- macOS (uses `osascript`)
- `jq`
- Accessibility permission for your terminal — System Settings → Privacy &
  Security → Accessibility. Without it the popup still appears, but no pick
  reaches the session.
- `TERMINAL_APP` in `scripts/notify-popup.sh` names the app to activate;
  Ghostty by default.
