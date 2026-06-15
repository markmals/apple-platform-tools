#!/usr/bin/env bash
# PreToolUse: block edits to generated / build artifacts that get rewritten by tooling.
set -euo pipefail

input=$(cat)
file_path=$(echo "$input" | jq -r '.tool_input.file_path // empty')
[[ -z "$file_path" ]] && exit 0

case "$file_path" in
    *.xcodeproj/* | *.xcworkspace/*)
        echo "Blocked: '$file_path' is a generated Xcode project. uitool builds with SwiftPM — edit Package.swift / Sources instead." >&2
        exit 2
        ;;
    */.build/* | */DerivedData/* | */.swiftpm/*)
        echo "Blocked: '$file_path' is a Swift build output. Edit the source under Sources/ and rebuild." >&2
        exit 2
        ;;
    */node_modules/*)
        echo "Blocked: '$file_path' is inside node_modules." >&2
        exit 2
        ;;
esac

exit 0
