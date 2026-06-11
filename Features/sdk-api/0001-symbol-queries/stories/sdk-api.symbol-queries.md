---
id: story.sdk-api.symbol-queries
kind: story
depends-on: [domain.agent-cli]
---

# Query SDK symbol existence and availability

**As a** coding agent
**I want** to query SDK symbol existence and availability
**So that** I don't write code against APIs that don't exist or aren't available on my deployment target.

**Independent test:** run `sdk-api check NSGlassEffectView.effectIsInteractive`
against the cached AppKit symbol graph and assert the JSON payload
(`exists`, `symbol`) and the exit code (0 when found, 1 when not).

## Acceptance Criteria

### Background

- Given the symbol graph for the queried module is available (extracted on first
  use and cached under `~/Library/Caches/sdk-api/<sdkVersion>/<module>/`)
- And the default module is AppKit unless `--module` overrides it

### Scenario 1: Checking a symbol that exists

<!-- id: scenario.sdk-api.symbol-queries.exists -->

- Given the AppKit symbol graph is available
- When the agent runs `sdk-api check NSGlassEffectView.effectIsInteractive`
- Then the tool emits `{query, exists: true, symbol: {…}}` with the symbol's
  name, qualified name, kind, and declaration
- And it exits 0

### Scenario 2: Checking a symbol that does not exist

<!-- id: scenario.sdk-api.symbol-queries.not-exists -->

- Given the AppKit symbol graph is available
- When the agent runs `sdk-api check NSGlassEffectView.notARealMember`
- Then the tool emits `{query, exists: false}` with no `symbol` field
- And it exits 1, so the agent can branch on existence without parsing prose

### Scenario 3: Reading a symbol's availability

<!-- id: scenario.sdk-api.symbol-queries.availability -->

- Given the AppKit symbol graph is available
- When the agent runs `sdk-api availability NSGlassEffectView`
- Then the tool emits `{symbol, matches: [{…, availability: {introduced, deprecated, obsoleted, message}}]}`
  for each matching declaration
- And it exits 0

### Scenario 4: Listing the members of a type

<!-- id: scenario.sdk-api.symbol-queries.members -->

- Given the AppKit symbol graph is available
- When the agent runs `sdk-api members NSGlassEffectView`
- Then the tool emits `{type, members: [{…}]}` listing the type's members in a
  stable order
- And it exits 0
