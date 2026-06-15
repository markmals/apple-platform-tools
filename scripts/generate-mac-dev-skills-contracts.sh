#!/usr/bin/env bash
set -euo pipefail

usage() {
  cat <<'EOF'
Usage: scripts/generate-mac-dev-skills-contracts.sh [--check] [--out DIR]

Generate the downstream CLI-contract reference files consumed by mac-dev-skills.
The source of truth is this repo's Specs/ and Features/ command/error files.

Options:
  --check    generate into a temp dir and fail if Exports/mac-dev-skills drifts
  --out DIR  write exports to DIR instead of Exports/mac-dev-skills
EOF
}

mode="write"
out_override=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --check)
      mode="check"
      shift
      ;;
    --out)
      out_override="${2:-}"
      if [[ -z "$out_override" ]]; then
        echo "--out requires a path" >&2
        exit 2
      fi
      shift 2
      ;;
    -h|--help)
      usage
      exit 0
      ;;
    *)
      echo "unknown argument: $1" >&2
      usage >&2
      exit 2
      ;;
  esac
done

script_dir="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
repo_root="$(cd "$script_dir/.." && pwd)"
default_out="$repo_root/Exports/mac-dev-skills"
out_root="${out_override:-$default_out}"

append_source() {
  local src="$1"
  local abs="$repo_root/$src"
  if [[ ! -f "$abs" ]]; then
    echo "missing source: $src" >&2
    exit 1
  fi
  {
    printf '\n## Source: `%s`\n\n' "$src"
    cat "$abs"
    printf '\n'
  } >>"$current_out"
}

start_file() {
  local rel="$1"
  local title="$2"
  current_out="$out_root/$rel"
  mkdir -p "$(dirname "$current_out")"
  cat >"$current_out" <<EOF
<!--
Generated from apple-platform-tools.
Do not edit downstream copies by hand; run scripts/generate-mac-dev-skills-contracts.sh.
-->

# $title

This file is the downstream-facing contract export for mac-dev-skills. It is
assembled from the apple-platform-tools spec library so CLI behavior changes
produce a mechanical diff downstream.
EOF
}

generate() {
  rm -rf "$out_root"

  start_file "appkit-design/references/apple-platform-tools-contracts.md" "sdk-api and sdk-search contracts"
  append_source "Specs/models/agent-cli.md"
  append_source "Features/sdk-api/0001-symbol-queries/commands/sdk-api.check.md"
  append_source "Features/sdk-api/0001-symbol-queries/commands/sdk-api.availability.md"
  append_source "Features/sdk-api/0001-symbol-queries/commands/sdk-api.members.md"
  append_source "Features/sdk-api/0001-symbol-queries/commands/sdk-api.enums.md"
  append_source "Features/sdk-api/0001-symbol-queries/commands/sdk-api.search.md"
  append_source "Features/sdk-search/0001-pattern-search/commands/sdk-search.search.md"
  append_source "Features/sdk-search/0001-pattern-search/commands/sdk-search.get.md"
  append_source "Features/sdk-search/0001-pattern-search/commands/sdk-search.list.md"
  append_source "Features/sdk-search/0001-pattern-search/commands/sdk-search.debug.md"

  start_file "appkit-app-inspector/references/cli-contract.md" "uitool CLI contract"
  append_source "Specs/models/agent-cli.md"
  append_source "Specs/models/domain.uitool.ipc.md"
  append_source "Features/uitool/0001-doctor/commands/uitool.doctor.md"
  append_source "Features/uitool/0001-doctor/commands/uitool.list-apps.md"
  append_source "Features/uitool/0002-attach/commands/uitool.launch.md"
  append_source "Features/uitool/0002-attach/commands/uitool.attach.md"
  append_source "Features/uitool/0002-attach/commands/uitool.detach.md"
  append_source "Features/uitool/0003-windows/commands/uitool.windows.md"
  append_source "Features/uitool/0004-tree/commands/uitool.tree.md"
  append_source "Features/uitool/0005-find/commands/uitool.find.md"
  append_source "Features/uitool/0006-node/commands/uitool.node.md"
  append_source "Features/uitool/0007-inspect/commands/uitool.inspect.md"
  append_source "Features/uitool/0008-schema/commands/uitool.schema.md"
  append_source "Features/uitool/0009-signing/commands/uitool.signing.md"
  append_source "Features/uitool/0010-classes/commands/uitool.classes.md"

  start_file "appkit-app-inspector/references/doctor-and-dev-box.md" "uitool doctor and development postures"
  append_source "Specs/models/domain.uitool.injection.md"
  append_source "Specs/models/domain.uitool.boot.md"
  append_source "Features/uitool/0001-doctor/commands/uitool.doctor.md"
  append_source "Features/uitool/0001-doctor/errors/uitool.doctor-precondition-failed.md"

  start_file "appkit-app-inspector/references/failure-signatures.md" "uitool failure signatures"
  append_source "Specs/models/domain.uitool.ipc.md"
  append_source "Features/uitool/0001-doctor/errors/uitool.doctor-precondition-failed.md"
  append_source "Features/uitool/0002-attach/errors/uitool.attach-injection-failed.md"
  append_source "Features/uitool/0002-attach/errors/uitool.attach-not-running.md"
  append_source "Features/uitool/0002-attach/errors/uitool.attach-precondition.md"
  append_source "Features/uitool/0002-attach/errors/uitool.attach-schema-mismatch.md"
  append_source "Features/uitool/0002-attach/errors/uitool.attach-timeout.md"
  append_source "Features/uitool/0002-attach/errors/uitool.launch-not-found.md"
  append_source "Features/uitool/0003-windows/errors/uitool.windows-no-windows.md"
  append_source "Features/uitool/0003-windows/errors/uitool.windows-not-attached.md"
  append_source "Features/uitool/0003-windows/errors/uitool.windows-timeout.md"
  append_source "Features/uitool/0004-tree/errors/uitool.tree-bad-projection.md"
  append_source "Features/uitool/0004-tree/errors/uitool.tree-stale-root.md"
  append_source "Features/uitool/0005-find/errors/uitool.find-bad-selector.md"
  append_source "Features/uitool/0005-find/errors/uitool.find-not-attached.md"
  append_source "Features/uitool/0005-find/errors/uitool.find-timeout.md"
  append_source "Features/uitool/0006-node/errors/uitool.node-stale.md"
  append_source "Features/uitool/0006-node/errors/uitool.node-value-timeout.md"

  start_file "appkit-app-inspector/references/filter-drill-and-selectors.md" "uitool selectors, predicates, and node ids"
  append_source "Specs/models/domain.uitool.selector.md"
  append_source "Specs/models/domain.uitool.node-id.md"
  append_source "Specs/models/domain.uitool.node.md"
  append_source "Features/uitool/0005-find/commands/uitool.find.md"
  append_source "Features/uitool/0004-tree/commands/uitool.tree.md"
  append_source "Features/uitool/0006-node/commands/uitool.node.md"

  start_file "appkit-private-apis/references/header-dumper.md" "headerdump contract"
  append_source "Features/headerdump/0001-dump-framework/commands/headerdump.dump.md"

  start_file "appkit-private-apis/references/redump.md" "redump contract"
  append_source "Specs/models/agent-cli.md"
  append_source "Features/redump/0001-binary-info/commands/redump.info.md"
  append_source "Features/redump/0001-binary-info/commands/redump.segments.md"
  append_source "Features/redump/0001-binary-info/commands/redump.symbols.md"
  append_source "Features/redump/0001-binary-info/commands/redump.imports.md"
  append_source "Features/redump/0001-binary-info/commands/redump.exports.md"
  append_source "Features/redump/0001-binary-info/commands/redump.strings.md"
  append_source "Features/redump/0002-disassembler/commands/redump.backends.md"
}

if [[ "$mode" == "check" ]]; then
  tmp="$(mktemp -d)"
  trap 'rm -rf "$tmp"' EXIT
  out_root="$tmp/mac-dev-skills"
  generate
  if ! diff -qr "$default_out" "$out_root"; then
    cat >&2 <<'EOF'

mac-dev-skills contract exports drifted.
Run:
  scripts/generate-mac-dev-skills-contracts.sh
EOF
    exit 1
  fi
else
  generate
fi
