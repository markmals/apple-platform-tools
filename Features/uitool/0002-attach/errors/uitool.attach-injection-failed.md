---
id: error.uitool.attach-injection-failed
kind: error
depends-on: [domain.uitool.injection, domain.uitool.ipc, command.uitool.attach, command.uitool.launch]
---

# Injection did not take

## When this happens

The injected channel never opens within the bounded wait — the [[domain.uitool.boot]] dylib failed to load (a `launch` spawn that did not exec, or a constructor that never started the server), or (on the attach-to-running path) the remote `dlopen` was refused. This is the failure [[domain.uitool.injection]] warns is otherwise silent: "any one link failing silently produces 'dylib didn't load'."

## What the user sees

Exit code 4 ([[domain.uitool.ipc]]) and a one-line structured JSON error on stderr naming the cause and a recovery hint — never a stack trace. The agent is never told the attach succeeded.

> `{"ok":false,"error":{"code":"INJECTION_FAILED","message":"socket never appeared for pid 4821 within the bounded wait","recover":"run uitool doctor to identify the failing link; if attach-to-running was refused, try uitool launch for a clean-launch instance"}}`

The wire `error.code` for injection-not-taking is `INJECTION_FAILED` (exit 4) — canonical.

## What the user can do

- Run `uitool doctor` to localize which precondition or arch link is failing (it reports exactly which, per [[domain.uitool.injection]]).
- If attach-to-running was refused for a target, try `uitool launch` for a fresh instance; accept that some targets are out of scope and do not burn schedule defeating them.

## Underlying cause (informational)

- dyld silently rejected the dylib (e.g. a plain-arm64 dylib into an arm64e process), or the constructor never started the server, so the socket at `/tmp/uitool-<pid>.sock` ([[domain.uitool.ipc]]) never appeared.
- On the attach-to-running path, `task_for_pid` was refused (the target is not `get-task-allow`, or `uitool` is not debugger-entitled), or the remote `dlopen` into the target failed ([[domain.uitool.injection]]).

## Related

- [[command.uitool.attach]] / [[command.uitool.launch]] — the verbs that surface this.
- [[error.uitool.attach-precondition]] — distinct: the preconditions themselves failed (exit 6), detected before injection is attempted.
- [[story.uitool.attach-inject]] — scenario.uitool.attach-inject.injection-failed; [[story.uitool.launch]] — scenario.uitool.launch.injection-failed.
