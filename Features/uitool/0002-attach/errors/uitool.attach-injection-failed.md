---
id: error.uitool.attach-injection-failed
kind: error
depends-on: [domain.uitool.injection, domain.uitool.ipc, command.uitool.attach]
---

# Injection did not take

## When this happens

The target is running and the preconditions pass, but the injected channel never opens within the bounded wait — the dylib failed to load, or (on Path B) the running-process attach was refused. This is the failure [[domain.uitool.injection]] warns is otherwise silent: "any one link failing silently produces 'dylib didn't load'."

## What the user sees

Exit code 4 ([[domain.uitool.ipc]]) and a one-line structured JSON error on stderr naming the cause and a recovery hint — never a stack trace. The agent is never told the attach succeeded.

> `{"ok":false,"error":{"code":"INJECTION_FAILED","message":"socket never appeared for pid 4821 within the bounded wait","recover":"run uitool doctor to identify the failing link; for hardened first-party targets the default running-attach path may be refused — retry with --relaunch"}}`

The wire `error.code` for injection-not-taking is `INJECTION_FAILED` (exit 4) — canonical.

## What the user can do

- Run `uitool doctor` to localize which precondition or arch link is failing (it reports exactly which, per [[domain.uitool.injection]]).
- For a first-party target on Path B, accept that some targets are out of scope and do not burn schedule defeating them; try a reachable target or the relaunch path.

## Underlying cause (informational)

- dyld silently rejected the dylib (e.g. a plain-arm64 dylib into an arm64e process), or the constructor never started the server, so the socket at `/tmp/uitool-<pid>.sock` ([[domain.uitool.ipc]]) never appeared.
- On Path B, `task_for_pid` / processor-set thread-hijack was refused by a protected target ([[domain.uitool.injection]]).

## Related

- [[command.uitool.attach]] — the verb that surfaces this.
- [[error.uitool.attach-precondition]] — distinct: the preconditions themselves failed (exit 6), detected before injection is attempted.
- [[story.uitool.attach-inject]] — scenario.uitool.attach-inject.injection-failed.
