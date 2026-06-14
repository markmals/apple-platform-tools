---
id: error.uitool.launch-not-found
kind: error
depends-on: [domain.uitool.ipc, command.uitool.launch]
---

# App to launch was not found

## When this happens

The agent launches a target by bundle id or path, but no launchable `.app`
bundle resolves — a misspelled bundle id, a bundle id for an app that is not
installed, or a path that does not point at a valid app bundle. This is the
launch-time analog of [[error.uitool.attach-not-running]]: `attach` fails when a
named **running process** does not exist; `launch` fails when a named
**installable app** does not exist.

## What the user sees

Exit code 3 ([[domain.uitool.ipc]]) and a one-line structured JSON error on
stderr naming the cause and a recovery hint — never a stack trace.

> `{"ok":false,"error":{"code":"APP_NOT_FOUND","message":"no launchable app for com.example.SampleAppKit","recover":"check the bundle id, or pass a path to the .app bundle"}}`

The wire `error.code` for a launch target that cannot be resolved is
`APP_NOT_FOUND` (exit 3) — canonical. Like `APP_NOT_RUNNING`
([[error.uitool.attach-not-running]]), it is a **launch-time** code, not a
post-socket wire code: it is raised by `launch` while resolving the target,
before any injection or socket ([[domain.uitool.ipc]] — exit 3 is attach/launch
time only).

## Distinct from the already-running case

Refusing to launch because a same-user instance is **already running** (without
`--replace`) is a different condition: it is a usage error (exit 2), not
`APP_NOT_FOUND`, and its recovery hint points at [[command.uitool.attach]] or
`--replace` ([[command.uitool.launch]] Behavior step 2). `APP_NOT_FOUND` means
*there is no such app to launch*; the exit-2 case means *the app is right there,
already running — say how you want it handled*.
