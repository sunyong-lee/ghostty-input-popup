# ghostty-input-popup

A Claude Code plugin that shows a macOS popup dialog with the actual pending
question whenever a session is idle or waiting on a permission decision —
so you never lose track of which of your concurrent sessions needs a reply.

## Install

```
/plugin marketplace add sunyong-lee/ghostty-input-popup
/plugin install ghostty-input-popup@personal-plugins
```

## How it works

Registers a `Notification` hook (matching `permission_prompt|idle_prompt`)
that runs `scripts/notify-popup.sh`. The script reads the session's
transcript and extracts the last assistant block, then answers it in place:

| Waiting on | Popup |
|---|---|
| An `AskUserQuestion` | One `choose from list` per question. Every pick is collected first, then replayed as arrow keys — so Dismiss at any point sends nothing at all. |
| Anything else | A `display dialog` with a text field. Whatever you type goes to the terminal via the clipboard, so Korean and emoji survive. |

Each fire appends one line to `~/.claude/ghostty-input-popup.log` recording
what the transcript held at that moment.

Answering from the popup drives the terminal by synthetic keystrokes, so
macOS needs Accessibility permission for your terminal app: System Settings
→ Privacy & Security → Accessibility → enable Ghostty. Without it the popup
still appears, but nothing reaches the session.

## Requirements

- macOS (uses `osascript`)
- `jq`
