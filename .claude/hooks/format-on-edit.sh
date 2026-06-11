#!/usr/bin/env bash
# PostToolUse: format the touched Swift file via the root `fmt` task.
#
# Only Swift sources are auto-formatted; specs (markdown) and configs are left as
# written. Best-effort: any failure — tool missing, package not yet scaffolded — is
# silenced so the agent's edit isn't disrupted.
set -euo pipefail

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[[ -z "$file_path" || ! -f "$file_path" ]] && exit 0

case "$file_path" in
    *.swift) (cd "$CLAUDE_PROJECT_DIR" && mise run fmt -- "$file_path") 2>/dev/null || true ;;
esac
exit 0
