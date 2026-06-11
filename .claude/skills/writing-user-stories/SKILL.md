---
name: writing-user-stories
description: Use when writing or reviewing user stories, acceptance criteria, or Gherkin scenarios (Given/When/Then) — including PRDs, tickets, specs, or feature plans. Trigger when output is a user-facing capability described from the user's perspective, not when designing APIs, schemas, or technical RFCs.
---

# Writing User Stories

A user story describes **one user-observable capability** in plain language, paired with **Gherkin acceptance criteria** that are externally testable. The story is the _what and why_; acceptance criteria are the _contract_.

**Core principle:** _Imagine it's 1922._ Most software does something a person could do manually, just less efficiently. If your story or scenarios depend on a particular UI, framework, endpoint, or database, you have written implementation, not a user story.

## When to Use

- Drafting or reviewing a user story, ticket, or PRD section describing a user-facing feature
- Writing acceptance criteria as Gherkin (Given/When/Then) scenarios
- Splitting a too-large story into smaller deliverable stories
- Reviewing a story for anti-patterns before handoff to engineering or design

**Do NOT use this skill for:**

- API contracts, data models, or technical architecture documents
- Internal-only system behavior with no user actor
- Project-specific naming or process conventions (those belong in CLAUDE.md)

## Story Format

```md
**As a** [real user persona]
**I want** [capability the user performs]
**So that** [user-visible outcome or value]
```

**Rules:**

- The _user_ must be a real human actor — not "system," "service," "scheduler," or "API."
- The _want_ is something the user does, not how the system implements it.
- The _so that_ expresses value or outcome the user perceives, not internal mechanics.

**Voice & abstraction:**

- Always from the user's point of view, in plain language a non-technical stakeholder understands.
- High enough to avoid prescribing solutions; concrete enough to be testable.
- Use consistent terminology — no synonyms for the same concept unless intentional.

**Don't:** "System writes CSV file to S3"
**Do:** "The user can download their data as a CSV file"

## One Story = One Capability

A story delivers **one user-observable capability**. If acceptance criteria branch into unrelated behavior — _sharing_ + _revoking_ + _audit logs_ + _rate limiting_ — the story is too large. Split it.

Symptoms of a too-large story:

- More than ~6 scenarios, especially covering different verbs (export, revoke, audit)
- Scenarios for cross-cutting concerns (accessibility, rate limiting, telemetry) bundled with the core capability
- "Out of Scope" or "Non-Functional Requirements" sections smuggling extra behavior into the story

Cross-cutting concerns (a11y, performance, security, audit) belong in their own stories or in shared definition-of-done standards, not piled into a feature story.

## Avoid the "How"

User stories describe **what and why**, never **how**:

- No frameworks, components, or libraries
- No endpoints, routes, or HTTP status codes
- No data models, tables, or storage details
- No specific UI elements (buttons, dialogs, dropdowns) by name

These belong in technical architecture or Figma designs, applied evenly across stories.

## Acceptance Criteria (Gherkin)

Acceptance criteria are the **contract** of the story: testable, externally observable behavior, mapped directly to Gherkin scenarios.

### Structure

```md
# Acceptance Criteria

## Scenario 1: [Specific behavior in plain language]

- Given [initial state]
- And [additional state]
- When [single user action]
- Then [observable outcome]
- And [additional outcome]
```

For scenarios with many additional details, indented lists read better than chains of `And`:

```md
## Scenario 1: [Specific behavior]

- Given [initial state]
    - [additional state]
    - [more state]
- When [single user action]
- Then [observable outcome]
    - [additional outcome]
```

### Given = State, Not Actions

`Given` describes the **scene** — what happened _before_ the user starts interacting. Setup conditions only; no user intent.

**Don't:** `Given the user clicks the export button`
**Do:** `Given the user is signed in` / `Given the user has recorded transactions`

Use vivid, named characters when helpful — `"Dr. Bill"` is easier to track than `"User A"`.

### When = Exactly One Trigger

One user action or system event per scenario. No branching, no compound actions.

**Don't:**

```md
- When I open the Share dialog
- And I enter Jordan's email
- And I select "Can view"
- And I click "Share"
```

**Do:**

```md
- When the user shares the document with a teammate as a viewer
```

If you have multiple `When`s, you have multiple scenarios — split them.

### Then = Observable Outcomes

Only what the user can **see, receive, or experience**. Never internal system behavior.

**Don't:**

- `Then an audit log entry is created` (internal)
- `Then Jordan is added to the access list with "Viewer" permission` (database state)
- `Then the request is rejected with a 403 Forbidden response` (HTTP detail)
- `Then the file is encoded as UTF-8 with a BOM per RFC 4180` (implementation)
- `Then the system queues the export as a background job` (internal)

**Do:**

- `Then the teammate can open the document in read-only mode`
- `Then the user receives a downloadable CSV file`
- `Then the user is told they don't have permission to do this`

If you find yourself wanting to verify a database row, log entry, queue, or HTTP code, step back: what does the **user actually observe**? That's the `Then`.

### Avoid UI Implementation in Steps

Express **intent**, not mechanics. UI choices belong in design, not in acceptance criteria.

**Don't:** `When the user clicks the green export button in the top right`
**Do:** `When the user requests a data export`

**Don't:** `When I open the Share dialog and type Jordan's email into the recipient field`
**Do:** `When I share the document with Jordan`

### And, But

Successive `Given`s or `Then`s read better with `And`/`But`:

```md
- Given I am signed in
- And I have recorded transactions
- When I request a data export
- Then I receive a CSV file
- And the file contains all my recorded transactions
```

Never use `And` to hide multiple `When` assertions — that's two scenarios.

### Background

Repeated `Given` steps across every scenario in a story are _incidental_ — move them to a `Background` section that runs before each scenario.

```md
# Acceptance Criteria

## Background

- Given a global administrator named "Greg"
    - A blog named "Greg's anti-tax rants"
    - A customer named "Dr. Bill"
    - A blog named "Expensive Therapy" owned by "Dr. Bill"

## Scenario 1: Dr. Bill posts to his own blog

- Given I am logged in as Dr. Bill
- When I post to "Expensive Therapy"
- Then I see "Your article was published."

## Scenario 2: Dr. Bill posts to somebody else's blog

- Given I am logged in as Dr. Bill
- When I post to "Greg's anti-tax rants"
- Then I see "Hey! That's not your blog!"
```

**Background tips:**

- Keep it short (≤ 4 lines). Readers must remember it while reading scenarios.
- Use vivid, story-like names — the brain tracks stories better than `User A`/`Site 1`.
- One Background per story. If you need different setups for different scenarios, the story is too large; split it.

## Worked Example

```md
# User Story

**As a** signed-in customer
**I want** to download my transaction history
**So that** I can keep my own records and use the data in other tools.

# Acceptance Criteria

## Scenario 1: Exporting personal data as CSV

- Given the user is signed in
- And the user has recorded transactions
- When the user requests a data export
- Then the user receives a CSV file
- And the file contains all recorded transactions

## Scenario 2: Exporting data with no records

- Given the user is signed in
- And the user has no recorded transactions
- When the user requests a data export
- Then the user receives a CSV file
- And the file contains only column headers
```

Two scenarios. One capability. No UI mechanics. No filenames, encodings, status codes, audit trails, or queues. The user perspective is intact end-to-end.

## Red Flags — Stop and Rewrite

If you see any of these in a step, the scenario is wrong:

| Red flag in step                                                                | Why it's wrong                                  | Fix                                                   |
| ------------------------------------------------------------------------------- | ----------------------------------------------- | ----------------------------------------------------- |
| `click`, `tap`, `drag`, `select from dropdown`, `type into field`               | UI mechanic, not user intent                    | Describe what the user is _trying to do_              |
| Specific UI element names: "Export button", "Share dialog", "recipient field"   | Prescribes design                               | Describe the action abstractly                        |
| Multiple `When`s in one scenario                                                | Compound trigger                                | Split scenarios, or collapse to one user-level action |
| `audit log`, `database`, `queue`, `cache`, `record is created`                  | Internal state                                  | Replace with what the user observes                   |
| HTTP codes (`403`, `404`), endpoints, payloads                                  | API detail                                      | Replace with the user-facing message or behavior      |
| File encodings, byte order marks, RFC numbers, p95 latency, sub-second timings  | Implementation/NFR                              | Move to architecture docs or NFR standards            |
| `OR`, `either/or`, branching inside a step                                      | Two scenarios in one                            | Split into separate scenarios                         |
| `Given the user clicks…` / `Given the user opens…`                              | Action in `Given`                               | Move to `When`, or rewrite as state                   |
| `Then the system…`, `Then the backend…`, `Then the service…`                    | Non-user actor in outcome                       | Rewrite from the user's perspective                   |
| Story has 10+ scenarios spanning multiple verbs (share + revoke + audit + a11y) | Too-large story                                 | Split into multiple stories, one capability each      |
| "Definition of Done" / "Non-Functional Requirements" sections inside the story  | Smuggling implementation/NFRs into a user story | Move to engineering doc / DoD standard                |

## Common Mistakes

**Multiple capabilities in one story.** A "share document" story that also covers revocation, audit logs, rate limiting, and accessibility is four or five stories. Split before you write scenarios.

**Givens that are actions.** `Given I open the dialog` is a `When`. `Given` is the _state of the world before the user does anything_.

**Thens that verify internal state.** "An entry is created", "the queue receives a job", "the audit log records the action" — none of these are observable. Replace with the user-visible result, or drop them.

**UI element names baked in.** "The green Export button in the top right" couples the story to a specific design. The user _requests an export_; how that looks is design's call.

**Status codes and endpoints.** `Then the request returns 403` is an API contract assertion, not a user story outcome. The user _sees a permission-denied message_ — that's the acceptance criterion.

**"And" hiding extra Whens.** `When I open the dialog and enter an email and click Share` is three actions. One scenario, one trigger.

## Anti-Patterns

- Encoding UI layout, element, or component names
- Referencing services, APIs, endpoints, databases, queues, or caches
- Writing conditionals or branches inside steps
- Using `And` to chain multiple `When` assertions
- Writing scenarios that can only be verified by inspecting internal state
- Mixing functional acceptance criteria with non-functional requirements (latency, throughput, retention) in the same scenario block
