# 0002 — Inject & detach

Covers getting FLEX-mac into a target process and tearing it down: `attach` (running-attach via Path B by default, or relaunch-inject via Path A with `--relaunch`), which opens the per-pid socket and bumps the session epoch, and `detach`, which closes the socket and drops the registry. Both verbs are idempotent. Spans milestones M0 (inject + load + ping against the harness) through M5 (first-party injection).

Depends on [[domain.uitool.injection]] (precondition stack, attach paths, lifecycle) and [[domain.uitool.ipc]] (the socket transport and exit-code mapping). Node ids and the epoch they carry are defined in [[domain.uitool.node-id]].
