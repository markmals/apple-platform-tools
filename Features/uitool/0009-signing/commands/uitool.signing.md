---
id: command.uitool.signing
kind: command
depends-on: [domain.uitool.injection, domain.uitool.ipc, story.uitool.signing-read]
---

# `uitool signing` — read a target's code signature

## Synopsis

```
uitool signing <pid|bundle-id|path> [--pretty]
```

## Inputs

| Input | Type | Required | Notes |
| --- | --- | --- | --- |
| `<pid\|bundle-id\|path>` | string | yes | a running pid, a bundle id, or a path to a `.app` / executable |
| `--pretty` | flag | no | pretty-print the JSON object. Default off |

No injection, no attach — `signing` reads the signature off the target's binary.

## Behavior

1. Resolve `<target>` to a binary path: a pid → its executable; a bundle id → the app's executable; a path → the executable inside a `.app`, or the file itself. If none resolves, fail (exit 3, app not found).
2. Read the code signature via the Security framework (signing info + entitlements + CS flags).
3. Derive the **cooperative-injectability** verdict from the facts ([[domain.uitool.injection]] — see Verdict).
4. Emit the report (exit 0).

## Output

A single JSON object on stdout. Deterministic: stable key order, no addresses.

```jsonc
{
  "target": "com.example.SampleAppKit",
  "signed": true,
  "identifier": "com.example.SampleAppKit",   // the code-signing identifier, or null
  "teamId": null,                              // TeamIdentifier, or null (ad-hoc / unsigned)
  "authority": "ad-hoc",                       // "ad-hoc", the leaf authority CN, or "unsigned"
  "hardenedRuntime": false,                    // the CS_RUNTIME flag
  "sandboxed": false,                          // com.apple.security.app-sandbox
  "getTaskAllow": true,                        // com.apple.security.get-task-allow — the cooperative lever
  "entitlements": {                            // the injection-relevant entitlements only
    "com.apple.security.get-task-allow": true
  },
  "cooperativeInjectable": true                // the derived verdict (see below)
}
```

The `entitlements` object carries only the injection-relevant keys
([[domain.uitool.injection]]): `get-task-allow`, `com.apple.security.cs.debugger`,
`com.apple.security.cs.disable-library-validation`,
`com.apple.security.cs.allow-dyld-environment-variables`,
`com.apple.security.app-sandbox` — not the full plist.

### Verdict

`cooperativeInjectable` is **true** when the target accepts cooperative injection on
a stock Mac ([[domain.uitool.injection]] Posture 1): it carries `get-task-allow`,
**and** either the hardened runtime is off **or** it grants both the dyld-environment
and disable-library-validation overrides (so `DYLD_INSERT` and an unsigned-by-Apple
dylib are honored). A target without `get-task-allow` is `false` — it needs the
unrestricted posture (the defanged box).

## States & exit codes

| State | Exit | stdout / stderr |
| --- | --- | --- |
| read | 0 | the report on stdout |
| usage | 2 | structured error on stderr |
| target not found | 3 | structured error on stderr |

No `4`/`5`/`6`/`7` — `signing` opens no socket and injects nothing.

## Invariants

- **Static and read-only.** No injection, no attach, no mutation; reads the
  signature off disk / the running binary.
- **Deterministic.** Stable key order; the injection-relevant entitlement subset is
  fixed.
- **The verdict follows [[domain.uitool.injection]].** `cooperativeInjectable`
  encodes Posture 1's per-target preconditions, so it stays in step with the
  injection model.

## Notes

- **Cost tier: cheap.** One Security-framework read; no target code runs.
- Complements `doctor`: `doctor` reports the *machine* posture, `signing` the
  *target* posture. Together they answer "can I inspect this app from here?"
- For a running pid, the signature is read from the process's executable path; a
  freshly re-signed binary (e.g. `mise run uitool-sign`) reflects immediately.
