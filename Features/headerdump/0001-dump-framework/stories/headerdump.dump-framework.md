---
id: story.headerdump.dump-framework
kind: story
depends-on: []
---

# Extract a framework's private ObjC and Swift headers

**As a** coding agent
**I want** to extract a framework's private ObjC and Swift headers to files
**So that** I can read the real API surface Apple doesn't publish.

**Independent test:** run `headerdump -o <outDir> <framework>` against a fixture
image with known Objective-C and Swift metadata, then assert the expected `.h`
files (per class/protocol/category) and `<Module>.swiftinterface` exist under
`<outDir>` with the recovered declarations, and that the process exits 0.

## Acceptance Criteria

### Background

- Given an output directory and a Mach-O image (a file, a bundle, or an image in
  the dyld shared cache) carrying Objective-C and/or Swift metadata

### Scenario 1: Dumping Objective-C class, protocol, and category headers

<!-- id: scenario.headerdump.dump-framework.objc -->

- Given a Mach-O image with `__objc_*` metadata for classes, protocols, and categories
- When the agent runs `headerdump -o <outDir> <image>`
- Then the tool writes one `.h` per Objective-C class, protocol, and category to `<outDir>`
- And each header carries the recovered declaration (superclass, ivars, properties, methods)
- And it exits 0

### Scenario 2: Writing a .swiftinterface for a Swift module

<!-- id: scenario.headerdump.dump-framework.swift -->

- Given a Mach-O image with `__swift5_*` metadata for a Swift module named `<Module>`
- When the agent runs `headerdump -o <outDir> <image>`
- Then the tool writes `<Module>.swiftinterface` to `<outDir>` with the recovered Swift declarations
- And an empty (whitespace-only) interface is not written
- And it exits 0

### Scenario 3: Resolving an image from the dyld shared cache

<!-- id: scenario.headerdump.dump-framework.shared-cache -->

- Given a system framework whose bytes live only in the dyld shared cache
- When the agent runs `headerdump -c -o <outDir> /System/Library/.../Foo.framework`
- Then the tool resolves the image from the shared cache (trying versioned path variants)
- And it writes the recovered ObjC and Swift headers to `<outDir>`
- And it exits 0

### Scenario 4: Recursively walking a directory or bundle tree

<!-- id: scenario.headerdump.dump-framework.recursive -->

- Given a directory tree containing one or more framework/app/bundle images
- When the agent runs `headerdump -r -o <outDir> <sourcePath>`
- Then the tool walks the tree, resolving each bundle to its executable image
- And it writes the recovered headers for every supported image it finds
- And it exits 0
