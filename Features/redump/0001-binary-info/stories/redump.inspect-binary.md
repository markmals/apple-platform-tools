---
id: story.redump.inspect-binary
kind: story
depends-on: [command.redump.info, domain.macho-image]
---

# Inspect a binary's shape without a disassembler

As a coding agent,
I want the architectures and file type of a Mach-O binary as JSON,
so that I can reason about what I'm looking at before reaching for a disassembler or extracting headers.

## Acceptance Criteria

## Scenario 1: A thin binary reports its single architecture

<!-- id: scenario.redump.inspect-binary.thin -->

- Given a thin Mach-O (one architecture)
- When the agent runs `redump info <binary>`
- Then the JSON reports `archs` with that one architecture, the `fileType`, and the `bitness`

## Scenario 2: A universal binary reports every slice

<!-- id: scenario.redump.inspect-binary.fat -->

- Given a universal (fat) Mach-O with multiple slices
- When the agent runs `redump info <binary>`
- Then `archs` lists every slice's architecture, in file order

## Scenario 3: A non–Mach-O path is rejected

<!-- id: scenario.redump.inspect-binary.unreadable -->

- Given a path that is not a readable Mach-O
- When the agent runs `redump info <path>`
- Then the tool exits non-zero with a diagnostic on stderr (no partial JSON on stdout)
