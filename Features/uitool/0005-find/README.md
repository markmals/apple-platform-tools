# 0005 — Find (selector & predicate search)

Server-side selector and predicate search across a target app's live view tree: `uitool find` resolves a CSS-like class selector and/or a `--where` predicate **inside the injected process**, optionally counting matches (`--count-only`), capping results (`--limit`), and projecting narrow fields (`--fields`) so only matching nodes cross the wire. This is the cheap "locate few" entry point of the canonical loop (locate few → project narrow → read deep on the survivors).

Depends on [[domain.uitool.selector]] (the selector / `--where` / `--fields` grammar) and [[domain.uitool.node-id]] (the stable handles returned for survivors). It also references [[domain.uitool.ipc]] (exit-code mapping, wire shape) and [[domain.uitool.node]] (the fields it matches and projects).
