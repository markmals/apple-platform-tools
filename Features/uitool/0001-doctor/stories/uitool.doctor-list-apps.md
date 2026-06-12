---
id: story.uitool.doctor-list-apps
kind: story
depends-on: [domain.uitool.injection, domain.uitool.ipc]
---

# List attachable apps

**As a** coding agent choosing a target to inspect
**I want** the running processes I could attach to, each annotated with whether it is hardened and its architecture
**So that** I can pick a reachable target and set my expectations about how hard attachment will be.

# Acceptance Criteria

## Background

- Given no attachment is performed against any listed process
- And a known set of apps is running

## Scenario 1: Listing the running attachable apps

<!-- id: scenario.uitool.doctor-list-apps.list -->

- Given several GUI apps are running
- When the agent lists attachable apps
- Then each running app appears with its pid, bundle id, hardened flag, and architecture
- And the command exits 0

## Scenario 2: Filtering by name

<!-- id: scenario.uitool.doctor-list-apps.match -->

- Given an app whose name contains "Mail" is running
- And other apps whose names do not contain "Mail" are running
- When the agent lists attachable apps matching "Mail"
- Then only the apps whose name matches appear in the result
- And the command exits 0

## Scenario 3: A filter that matches nothing

<!-- id: scenario.uitool.doctor-list-apps.empty -->

- Given no running app's name matches "Nonesuch"
- When the agent lists attachable apps matching "Nonesuch"
- Then the result is an empty list of apps
- And the command exits 0 (an empty match is not an error)

## Scenario 4: Hardened first-party app is flagged

<!-- id: scenario.uitool.doctor-list-apps.hardened -->

- Given a hardened first-party app and a non-hardened harness app are both running
- When the agent lists attachable apps
- Then the first-party app is reported as hardened
- And the harness app is reported as not hardened
- And the command exits 0
