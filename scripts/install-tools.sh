#!/usr/bin/env bash
# Build, ad-hoc sign, and install the CLIs to ~/.local/bin.
#
# Installs all five tools — the SDK-knowledge, static-analysis, and runtime
# clusters. uitool ships with its injected boot dylib beside it and is signed
# with the debugger entitlement for the cooperative attach path (your own
# dev-signed apps on a stock Mac). See Specs/ARCHITECTURE.md → "Dual-use & safety".
#
# Override the install dir with SDK_TOOLS_BINDIR (default ~/.local/bin).
set -euo pipefail

# Distributable executables. Add a tool here once it is migrated in and safe to ship.
TOOLS=(sdk-api sdk-search headerdump redump)

root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
bindir="${SDK_TOOLS_BINDIR:-$HOME/.local/bin}"
cd "$root"
mkdir -p "$bindir"

# Build each product individually — a combined --product invocation has emitted
# only one binary under the current toolchain's build system.
for tool in "${TOOLS[@]}"; do
    echo "Building $tool (release)…"
    swift build -c release --product "$tool" >/dev/null
done

binpath="$(swift build -c release --show-bin-path)"

for tool in "${TOOLS[@]}"; do
    src="$binpath/$tool"
    [[ -x "$src" ]] || {
        echo "✗ $tool not found at $src" >&2
        exit 1
    }
    install -m 0755 "$src" "$bindir/$tool"
    codesign --force --sign - "$bindir/$tool" >/dev/null 2>&1 || true
    echo "✓ installed $bindir/$tool"
done

# SwiftPM resource bundles must sit next to the binary so Bundle.module resolves
# once the executable leaves the build dir (sdk-search's pattern corpus). Only
# the installed tools' bundles are present, since we built just their products.
shopt -s nullglob
for bundle in "$binpath"/*.bundle; do
    name="$(basename "$bundle")"
    rm -rf "${bindir:?}/$name"
    cp -R "$bundle" "$bindir/$name"
    echo "✓ installed $name"
done

# uitool is the runtime-introspection CLI. It needs its injected boot dylib
# (libUIToolBoot.dylib) beside it — BootDylib resolves the dylib next to the
# executable — and the debugger entitlement so `attach` can take a get-task-allow
# target's task port. This is the cooperative arm64 build; the arm64e unrestricted
# slice is a separate dev-box build.
echo "Building uitool + UIToolBoot (release)…"
swift build -c release --product uitool >/dev/null
swift build -c release --product UIToolBoot >/dev/null
install -m 0755 "$binpath/uitool" "$bindir/uitool"
install -m 0755 "$binpath/libUIToolBoot.dylib" "$bindir/libUIToolBoot.dylib"
codesign --force --sign - "$bindir/libUIToolBoot.dylib" >/dev/null 2>&1 || true
codesign --force --sign - --entitlements scripts/uitool-debugger.entitlements "$bindir/uitool" >/dev/null 2>&1 || true
echo "✓ installed $bindir/uitool (+ libUIToolBoot.dylib, debugger entitlement)"

echo
echo "Smoke test (from $bindir):"
"$bindir/sdk-api" --help >/dev/null && echo "  ✓ sdk-api"
"$bindir/sdk-search" list >/dev/null && echo "  ✓ sdk-search (corpus resolved)"
"$bindir/uitool" doctor >/dev/null && echo "  ✓ uitool (doctor)"

case ":$PATH:" in
    *":$bindir:"*) ;;
    *) echo && echo "Note: $bindir is not on your PATH — add it to run the tools by name." ;;
esac
