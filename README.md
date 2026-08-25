# ghostty-input-popup

A Claude Code plugin that pops up a macOS dialog whenever a session needs you —
and lets you answer from the dialog, so you never lose track of which of your
concurrent sessions is waiting.

## Install

```
/plugin marketplace add sunyong-lee/ghostty-input-popup
/plugin install ghostty-input-popup@personal-plugins
```

## What you get

| The session is | Popup | Answering |
|---|---|---|
| asking a question | one `choose from list` per question | pick one, it is sent for you |
| waiting for a prompt | `display dialog` with a text field | type a reply, it is sent for you |
| waiting on a permission decision | notice only | answer in the terminal |

Every pick is collected before anything is sent, so Dismiss at any point sends
nothing at all. Picks replay as arrow keys; typed text goes via the clipboard,
which keeps Korean and emoji intact.

## How it works

A `Notification` hook covers the prompt and permission cases. Questions cannot
work that way — Claude Code raises no notification when it asks one — so a
`SessionStart` hook starts `scripts/watch-questions.sh`, which polls the
transcript once a second and hands any pending question to the same popup
script. `SessionEnd` stops it.

The popup shows the notification's own message rather than the tail of the
transcript. That tail is usually the reply just given, which reads as the wrong
message entirely.

`~/.claude/ghostty-input-popup.log` gets one line per run — event type, what was
pending, first 80 characters. Start there when a popup surprises you.

## Tuning

The prompt popup rides on Claude Code's idle notification, 60 seconds by
default. For something quicker, set `messageIdleNotifThresholdMs` in
`~/.claude.json`:

```json
{ "messageIdleNotifThresholdMs": 10000 }
```

## Requirements

- macOS (uses `osascript`)
- `jq`
- Accessibility permission for your terminal — System Settings → Privacy &
  Security → Accessibility. Without it the popup still appears, but nothing
  reaches the session.

Answers land in whichever window is frontmost after the terminal is activated,
so with several sessions open they can go to the wrong one. `TERMINAL_APP` in
`scripts/notify-popup.sh` names the app to activate; Ghostty by default.
