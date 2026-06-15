#!/usr/bin/env bash
# Notification: surface a macOS notification when Claude Code needs attention.
set -euo pipefail

input=$(cat)
message=$(echo "$input" | jq -r '.message // "Claude Code needs attention"')

# Escape double quotes for AppleScript
escaped=$(printf '%s' "$message" | sed 's/"/\\"/g')

osascript -e "display notification \"$escaped\" with title \"Claude Code\" sound name \"Glass\"" 2>/dev/null || true

exit 0
