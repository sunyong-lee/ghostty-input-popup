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
transcript, extracts the last assistant message, and shows it in a native
`osascript display dialog` popup along with the project name.

## Requirements

- macOS (uses `osascript`)
- `jq`
