---
id: domain.macho-image
kind: domain
---

# Domain: Mach-O image loading

The shared image-loading model realized by the `BinaryFoundation` library and used by the static-analysis cluster (`headerdump`, and `redump`). It answers one question — "give me a usable Mach-O slice for this path" — from a file on disk or the active dyld shared cache. See `ARCHITECTURE.md` → "Shared foundations".

`BinaryFoundation` is **pure with respect to the process environment**: it never reads env vars. The set of dyld *runtime roots* (which a simulator orchestration supplies via `PH_RUNTIME_ROOT` / `DYLD_ROOT_PATH` / `SIMCTL_CHILD_DYLD_ROOT_PATH`) is read at the **tool's** edge and passed in as `runtimeRoots: [String]`. This is the seam that was factored out of headerdump's `HeaderDumpCore` (Phase 2a).

## API (`MachOImage`)

- **`load(at:useSharedCache:runtimeRoots:) -> MachOFile?`** — load a path as a supported Mach-O slice. Reads the file directly; for a universal (fat) binary, returns the first supported slice. Falls back to the dyld shared cache when `useSharedCache` is set or the file can't be read.
- **`isSupported(_:) -> Bool`** — true for `arm64` / `x86_64` slices only.
- **`loadFromSharedCache(imagePath:runtimeRoots:) -> MachOFile?`** — resolve an image out of the active dyld shared cache, trying the candidate paths below.
- **`normalizedCacheImagePaths(for:runtimeRoots:) -> [String]`** — the ordered, de-duplicated candidate cache paths for an image: the path itself, versioned framework variants (`Versions/{Current,A,B,C}/<name>`), each `runtimeRoot`-stripped form, and the canonical `/System/Library/…` and `/usr/lib/…` forms.
- **`sharedCachePath(runtimeRoots:fileManager:) -> String`** — the active dyld shared cache path: a runtime-root sim cache if one exists (arm64e then arm64), else the host cache (preferring arm64e, then the known cryptex / `/private/var/db/dyld` locations). `fileManager` is a `FileExistenceChecking` seam so tests can inject existence.

## Invariants

1. **Env-free.** No function reads `ProcessInfo.environment`; runtime roots are always parameters.
2. **First candidate is the input path.** `normalizedCacheImagePaths(for: p, …).first == p`.
3. **De-duplicated, order-preserving.** Candidate lists contain no duplicates and preserve discovery order.
4. **Only supported architectures load.** `load` returns `nil` for a slice that isn't arm64/x86_64.

## Acceptance

- A runtime-root sim cache is preferred over the host cache when it exists; otherwise the canonical host cache path is returned.
- Candidate paths for a framework image include its versioned variants and the runtime-root-stripped canonical form.
