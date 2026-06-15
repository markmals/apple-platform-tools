---
id: story.uitool.schema-print
kind: story
depends-on: [domain.uitool.node, domain.uitool.ipc]
---

# Discover the output contract from the tool

**As a** coding agent driving uitool
**I want** to read the tool's output contract as machine-readable JSON
**So that** I can parse every verb's output and branch on exit codes without
out-of-band documentation.

**Independent test:** Run `uitool schema`; observe a JSON object listing the node
record's fields (with default/`--include` flags and types) and the exit-code map,
with no app and no injection.

## Acceptance Criteria

### Scenario 1: Print the contract offline

<!-- id: scenario.uitool.schema-print.offline -->

- Given no app is attached and no target is supplied
- When the agent runs `uitool schema`
- Then it exits 0 with a JSON object describing the output records and the exit-code map
- And it touches no target — no socket, no injection

### Scenario 2: The node record lists default and include fields

<!-- id: scenario.uitool.schema-print.node-fields -->

- When the agent runs `uitool schema`
- Then the `node` record lists each field's name, type, and whether it is default or `--include`-only ([[domain.uitool.node]])
- And the default fields include `node`, `class`, and `frame`; the `--include` fields include `layer` and `constraints`

### Scenario 3: The contract is deterministic

<!-- id: scenario.uitool.schema-print.deterministic -->

- When the agent runs `uitool schema` twice
- Then the two outputs are byte-identical (stable key order, fixed content)
