# ghostty-input-popup

A Claude Code plugin that pops up a macOS dialog when a session asks you a
question and takes your answer there, so you never lose track of which of your
concurrent sessions is waiting — or go hunting for its window to reply.

Questions only, and nothing else. No popup while a session is merely idle or
waiting on a permission decision — a dialog with nothing to answer is noise.

## Install

```
/plugin marketplace add sunyong-lee/ghostty-input-popup
/plugin install ghostty-input-popup@personal-plugins
```

## What you get

The popup lists the question's options and takes your pick, so the session has
its answer without you finding the right terminal first.

Nothing traps you in the dialog. Cancel it, let it time out after two minutes, or
pick `(answer in the terminal instead)`, and it steps aside — the terminal picker
comes up as usual. A question with several parts asks them one at a time, and
abandoning any part hands the whole question back to the terminal: half an answer
is worse than none.

### Why replaying keystrokes was abandoned

Answering used to mean activating the terminal and replaying keys into it, and
AppleScript cannot address a particular window or tab — the keys went wherever
the frontmost window happened to be. In testing, answers landed in a different
session twice. Counting sessions first did not help, since sessions started
before the plugin are invisible to it.

The hook needs none of that. A pick travels back through the hook that asked, so
it cannot reach the wrong session.

## How it works

A `PreToolUse` hook matching the `AskUserQuestion` tool runs before the question
reaches you and hands `scripts/popup-from-hook.sh` the questions and their
options outright, so the dialog is built without reading anything. The hook waits
for your pick, which is why the terminal picker stays away while the dialog is up.

A `PreToolUse` hook cannot hand Claude a tool result, so the pick goes back the
only way there is: the tool call is denied and the pick rides along as
`permissionDecisionReason`. Cancelling or running out of time writes no decision
at all, which leaves the normal permission flow untouched.

`choose from list` has no `giving up after`, so the two-minute limit is kept in
the script rather than by AppleScript, which also means the dialog is killed
rather than left behind.

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
`SessionStart` and `SessionEnd`. The hook has since fired on real questions, so
they are dead weight and come out next.

`~/.claude/ghostty-input-popup.log` carries `"src":"hook"` on everything the hook
writes: a `"kind":"question"` line before the dialog opens, and a
`"kind":"answer"` line once a pick is delivered. A question line with no answer
line after it is one you left alone. Start there when a popup surprises you.

## Requirements

- macOS (uses `osascript`)
- `jq`
