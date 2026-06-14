# uitool — machine setup for live runtime inspection

This is the only part of the monorepo that needs special machine setup. The
SDK-knowledge tools (`sdk-api`, `sdk-search`) and the static-analysis tools
(`headerdump`, `redump`) run on any Mac with no configuration. **Only `uitool`**
— which injects an inspector into a live process — has machine requirements, and
how much you need depends entirely on **whose code signed the app you want to
inspect.**

> **The one idea that decides everything:** macOS gates injection **per target**,
> not per machine. There is no single "is my Mac ready?" — there are two
> questions, and the cheap one is the common one.

| You want to inspect… | Posture | Machine changes |
| --- | --- | --- |
| **An app you build and sign** (your own Debug builds) | **Cooperative** | **None.** SIP/AMFI/library-validation stay ON. |
| **An app you did *not* sign** (Mail, Finder, a notarized 3rd-party app) | **Unrestricted** | The full defang — SIP off, AMFI/ABI boot-args, library validation off. **Dedicated dev box only.** |

Reach for **cooperative** first. You almost never need the defang for your own
development. `uitool doctor` reports both postures and tells you which is usable.

---

## 0. Prerequisites (both postures)

- **Apple Silicon Mac** (M-series). Verify:
  ```sh
  uname -m         # arm64  → good
  ```
- Xcode + command-line tools, and this repo building (`mise run build` or `swift build`).

---

## 1. Cooperative posture — inspect your own apps (recommended)

For an app **you build and sign**, macOS already lets you in: a Debug build is
signed with `get-task-allow` (Xcode's default), the same entitlement that lets
lldb / Xcode / Reveal attach to your own apps. **No SIP, AMFI, or
library-validation changes. No reboot.** This works on a stock, fully-secured Mac.

There are two ways `uitool` gets in, with different requirements:

### 1a. `uitool launch` — start the app fresh under inspection (simplest)

Spawns the app with the inspector pre-loaded (`DYLD_INSERT_LIBRARIES`). You lose
whatever was on screen, but it needs the least setup.

1. **Build the arm64 boot dylib** (`UIToolBoot`). *(Not built yet — see
   [Current status](#current-status). Once it is, this is a build-script step;
   the signed dylib is git-ignored and never leaves the dev box.)*
2. **Your target must permit `DYLD_INSERT`.** A normal **Debug** build does
   (`get-task-allow`, hardened runtime off). If your build is hardened, add to its
   entitlements:
   - `com.apple.security.cs.allow-dyld-environment-variables` = `true`
   - `com.apple.security.cs.disable-library-validation` = `true`
3. Run it:
   ```sh
   uitool launch com.example.YourApp      # or a path to the .app
   uitool windows com.example.YourApp     # then read it live
   ```

### 1b. `uitool attach` — inspect an already-running app, keeping its state

Reaches into a running app without restarting it (lldb-style `task_for_pid` +
remote load), so the on-screen state is preserved.

1. Everything from 1a, **plus**
2. **`uitool` itself must be signed with the debugger entitlement** — the same
   one lldb carries — so it can acquire a `get-task-allow` target's task port:
   ```sh
   cat > /tmp/uitool.entitlements <<'EOF'
   <?xml version="1.0" encoding="UTF-8"?>
   <!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
   <plist version="1.0">
   <dict>
     <key>com.apple.security.cs.debugger</key>
     <true/>
   </dict>
   </plist>
   EOF
   codesign -s - --force --entitlements /tmp/uitool.entitlements "$(which uitool)"
   ```
3. The target must be the **same user** and `get-task-allow`. Then:
   ```sh
   uitool attach 4821        # by pid, or a running bundle id
   uitool tree 4821          # live state preserved
   ```

> **Cooperative checklist** (`uitool doctor` → `cooperative.usable`): Apple
> Silicon host ✔, arm64 `UIToolBoot` present ✔. That's the whole machine
> requirement. The target preconditions (`get-task-allow`, and the debugger
> entitlement on `uitool` for 1b) are checked at `attach`/`launch`, not by doctor.

---

## 2. Unrestricted posture — inspect apps you did *not* sign

A system or notarized app ships hardened with **no `get-task-allow` lever to
flip**, so the only way in is to lower the protections **machine-wide**. This is a
real, system-wide security regression.

> ⚠️ **Use a dedicated dev box that holds no real data.** Every step here is
> reversible from Recovery (see [§3](#3-reverting-the-defang)), but while it is in
> effect the machine is broadly less safe. Do not do this to your daily driver.
>
> ⚠️ **arm64e injection is actively regressing across Tahoe 26.x.** Pin one known
> 26.x build on the dev box; expect the unrestricted path to be fragile. The
> cooperative posture above is unaffected by this.

### 2a. Disable SIP (from Recovery)

1. Shut down. Press and **hold the power button** until "Loading startup
   options" appears → click **Options** → **Continue**.
2. **Utilities → Terminal**, then:
   ```sh
   csrutil disable
   ```
3. If you'll set custom kernel boot-args (next section) and they get ignored,
   also set the security policy to **Permissive Security**: Recovery →
   **Startup Security Utility** → select your system → **Security Policy…** →
   *Permissive Security*. (`csrutil disable` usually suffices on its own.)
4. Reboot into macOS.

### 2b. AMFI + the arm64e preview ABI (kernel boot-args)

`amfi_get_out_of_my_way=0x1` is the real gate; `-arm64e_preview_abi` lets
third-party arm64e code load against the arm64e shared cache. Set both at once:

```sh
sudo nvram boot-args="amfi_get_out_of_my_way=0x1 -arm64e_preview_abi"
```

### 2c. Disable library validation (system-wide)

```sh
sudo defaults write /Library/Preferences/com.apple.security.libraryvalidation.plist DisableLibraryValidation -bool true
```

### 2d. Reboot, then build the **arm64e** boot dylib

The unrestricted injectable must be **arm64e** to match the system frameworks
(the dyld shared cache is arm64e on Apple Silicon); a plain-arm64 dylib fails
`dyld` silently against a system target. *(Built by the build script with
`-arm64e_preview_abi`; git-ignored, dev-box only.)*

### Verify

```sh
csrutil status            # → "disabled" (or System Integrity Protection ... permissive)
nvram boot-args           # → shows amfi_get_out_of_my_way=0x1 -arm64e_preview_abi
uitool doctor             # → unrestricted.usable: true
```

> `uitool doctor --fix` can apply the **nvram** and **library-validation** steps
> for you (it echoes each command before running, never runs implicitly), but it
> **cannot** do SIP (Recovery only) or reboot — it prints exactly what's left.

---

## 3. Reverting the defang

Put the machine back (run the first two on the booted system, the last in
Recovery):

```sh
sudo nvram -d boot-args
sudo defaults delete /Library/Preferences/com.apple.security.libraryvalidation.plist DisableLibraryValidation
# then, from Recovery → Terminal:
csrutil enable
# reboot
```

If you set Permissive Security, raise it back to *Full Security* in Recovery →
Startup Security Utility.

---

## 4. Safety & containment (non-negotiable)

- **The signed `UIToolBoot` dylib never leaves the dev box.** It is a signed
  code-loading primitive — an attack tool on any other machine. It is
  `.gitignore`d, never committed, never added to a shippable target or release
  CI. The cooperative posture running on a stock Mac does **not** relax this.
- **Knowledge crosses into your products; the tool never does.** A resolved font,
  a constraint, a material name leaves the repo and informs real AppKit work. The
  injection step does not.
- **`uitool` is read-only.** v1 ships no write/mutation op.

---

## Current status

The setup above is the target state. As of this writing the injection half is
**partially built**:

- ✅ The pure projection core, the cheap-read verbs, `doctor`, the
  known-geometry oracle (`SampleAppKit`), the in-target server bridge
  (`UIToolServer`), and the **socket transport** (both ends) are done and tested
  on a stock Mac.
- ⏳ **`UIToolBoot`** (the boot dylib + its codesigning/build script) and the
  `launch`/`attach` wiring are the next slices. Until `UIToolBoot` is built,
  `uitool doctor` reports both postures' injectable as **absent** and exits 6 —
  the machine setup is correct, the dylib just isn't there yet.

So today: do the **cooperative** setup (it's nearly nothing), and the moment the
arm64 dylib lands you can `uitool launch` your own apps with zero machine changes.
Only set up the unrestricted defang when you actually need to inspect an app you
didn't sign.
