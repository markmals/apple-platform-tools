#!/usr/bin/env bash
# PostToolUse: format the touched Swift file with swift-format (the same tool the
# `fmt` mise task and the lint hook use; run per-file here so an edit doesn't
# reformat the whole tree).
#
# Only Swift sources are auto-formatted; specs (markdown) and configs are left as
# written. Best-effort: any failure — tool missing, package not yet scaffolded — is
# silenced so the agent's edit isn't disrupted.
set -euo pipefail

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[[ -z "$file_path" || ! -f "$file_path" ]] && exit 0

case "$file_path" in
    *.swift) (cd "$CLAUDE_PROJECT_DIR" && swift format --in-place "$file_path") 2>/dev/null || true ;;
esac
exit 0
