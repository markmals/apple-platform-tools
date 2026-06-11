---
id: story.redump.check-backends
kind: story
depends-on: [command.redump.backends]
---

# Check which disassembler backends are available

As a coding agent,
I want to know whether IDA Pro or Hopper is configured before I run a disassembler-backed command,
so that I fail fast with a clear reason instead of attempting analysis that can't run.

## Acceptance Criteria

## Scenario 1: No backend configured

<!-- id: scenario.redump.check-backends.none -->

- Given neither `RE_IDAT64` nor `RE_HOPPER` is set and no known install path exists
- When the agent runs `redump backends`
- Then both `ida` and `hopper` are reported with `configured: false` and a null `path`

## Scenario 2: A backend configured via environment

<!-- id: scenario.redump.check-backends.env -->

- Given `RE_HOPPER` points at a Hopper executable
- When the agent runs `redump backends`
- Then `hopper` is reported `configured: true` with that resolved `path`
