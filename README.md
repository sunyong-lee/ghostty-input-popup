# ghostty-input-popup

A Claude Code plugin that pops up a macOS dialog when a session asks you a
question, so you never lose track of which of your concurrent sessions is
waiting.

Questions only, and nothing else. No popup while a session is merely idle or
waiting on a permission decision — a dialog with nothing to answer is noise.

## Install

```
/plugin marketplace add sunyong-lee/ghostty-input-popup
/plugin install ghostty-input-popup@personal-plugins
```

## What you get

The popup shows the question and its numbered options, matching the numbering in
the terminal. You answer in the terminal; the dialog is there to tell you which
session is asking and what it wants.

It gives up after two minutes, so an unread one does not outlive its question and
stack up behind the next.

### Why it does not answer for you

Answering from the popup was built and removed. Sending a pick means activating
the terminal and replaying keys into it, and AppleScript cannot address a
particular window or tab — the keys go wherever the frontmost window happens to
be. In testing, answers landed in a different session twice. Counting sessions
first did not help, since sessions started before the plugin are invisible to it.

Delivering an answer to the wrong session is worse than not delivering one, so
the popup only reports.

## How it works

Claude Code raises no notification when it asks a question, so a hook cannot see
one. A `SessionStart` hook detaches `scripts/watch-questions.sh`, which reads the
transcript once a second and hands any pending question to
`scripts/notify-popup.sh`. `SessionEnd` removes the pidfile the watcher checks
each second; a session that dies without it gives up on a transcript left
untouched for 30 minutes.

Whether a question is still pending is decided by `scripts/pending-question.jq`,
shared so the watcher and the popup cannot disagree. An answer is recorded as a
user `tool_result`, not an assistant block, so a filter reading only assistant
blocks calls an answered question pending — which made popups appear just after
answering.

`~/.claude/ghostty-input-popup.log` gets one line per run — what was pending, the
question id, first 80 characters. Start there when a popup surprises you.

## Requirements

- macOS (uses `osascript`)
- `jq`
