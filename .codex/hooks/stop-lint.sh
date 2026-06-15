#!/usr/bin/env bash
# Stop: lint when Swift sources changed since HEAD. Blocks the stop (decision: block)
# if lint fails, so the agent fixes before declaring work done.
set -euo pipefail

input=$(cat)
stop_hook_active=$(echo "$input" | jq -r '.stop_hook_active // false')
[[ "$stop_hook_active" == "true" ]] && exit 0

cd "$CLAUDE_PROJECT_DIR"

# Nothing to lint until the SwiftPM package exists.
[[ -f Package.swift ]] || exit 0

if ! git diff --quiet HEAD -- '*.swift' 2>/dev/null; then
    if ! output=$(mise run lint 2>&1); then
        jq -n --arg reason "Lint failures before stop:

$output" '{decision: "block", reason: $reason}'
    fi
fi

exit 0
