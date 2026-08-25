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

A `PreToolUse` hook matching the `AskUserQuestion` tool runs before the question
reaches you and hands `scripts/popup-from-hook.sh` the questions and their
options outright, so the dialog is built without reading anything. The hook
detaches the dialog and returns at once — blocking there would hold the question
off the terminal until you closed it.

The `Notification` event is no help: it carries `permission_prompt` and
`idle_prompt`, but nothing for a question.

### Why polling the transcript was abandoned

Claude Code flushes the transcript at turn boundaries, so the record for a
question and the record for its answer arrive in the same write. While a question
is on screen there is nothing on disk to find. Measured on 2026-08-25: the file
sat untouched for the whole 12 seconds a question was up, then grew by six
records at once, question and answer together. A record's `timestamp` is when the
block was produced, not when it was written.

That single fact explains both symptoms this plugin has had. Before
`scripts/pending-question.jq` gained its answered-check, every popup arrived just
after answering. After it, the check correctly reports every question the watcher
ever sees as already settled — so questions produced no popup at all.

`scripts/watch-questions.sh` and `scripts/pending-question.jq` are still wired to
`SessionStart` and `SessionEnd`. They cannot fire for a question and are kept only
until the hook has proven itself.

`~/.claude/ghostty-input-popup.log` gets one line per run — what was pending, the
question id, first 80 characters. Lines from the hook carry `"src":"hook"`. Start
there when a popup surprises you.

## Requirements

- macOS (uses `osascript`)
- `jq`
