import AgentCLI
import AppKit
import Darwin
import Foundation
import UIToolCore
import UIToolIPC
import UIToolInject

// SPEC: domain.uitool.injection
/// Where the CLI finds the boot dylib to inject. An explicit `UITOOL_BOOT_DYLIB`
/// override wins; otherwise the dev layout — `libUIToolBoot.dylib` next to the
/// `uitool` executable (the `.build/debug` directory). The signed dylib is
/// git-ignored, dev-box only ([[domain.uitool.boot]] containment).
enum BootDylib {
  static let fileName = "libUIToolBoot.dylib"

  static func resolvedPath() -> String? {
    if let override = ProcessInfo.processInfo.environment["UITOOL_BOOT_DYLIB"] {
      return override
    }
    let exeDir =
      (Bundle.main.executableURL ?? URL(fileURLWithPath: CommandLine.arguments[0]))
      .resolvingSymlinksInPath()
      .deletingLastPathComponent()
    let candidate = exeDir.appendingPathComponent(fileName).path
    return FileManager.default.fileExists(atPath: candidate) ? candidate : nil
  }

  /// The dylib path, or a precondition failure naming the fix.
  static func require() throws -> String {
    guard let path = resolvedPath() else {
      throw UIToolError.preconditionFailed(
        "\(fileName) not found — build it (swift build) or set UITOOL_BOOT_DYLIB")
    }
    return path
  }
}

// SPEC: domain.uitool.injection
/// One inspection session, established by `launch` or `attach`. Pure data the
/// command projects into its result object.
struct Session {
  let pid: pid_t
  let bundleId: String?
  /// "launch" (spawn-inject) or "running" (attach-to-running).
  let path: String
  let replaced: Bool
  let reused: Bool
  let epoch: Int
}

// SPEC: command.uitool.launch
/// The deterministic result object `launch` / `attach` emit. `replaced` is a launch
/// fact, `reused` an attach fact; the inapplicable one is omitted. `sessionId` (the
/// wire form of the session epoch) is stripped by `--no-meta` for byte-stability.
struct SessionResult: Encodable {
  let ok: Bool
  let target: Target
  let path: String
  let channel: String
  let schemaVersion: String
  let replaced: Bool?
  let reused: Bool?
  let sessionId: String?

  struct Target: Encodable {
    let pid: Int
    let bundleId: String?
  }

  static func from(_ session: Session, noMeta: Bool) -> SessionResult {
    SessionResult(
      ok: true,
      target: Target(pid: Int(session.pid), bundleId: session.bundleId),
      path: session.path,
      channel: "open",
      schemaVersion: Schema.version,
      replaced: session.path == "launch" ? session.replaced : nil,
      reused: session.path == "running" ? session.reused : nil,
      sessionId: noMeta ? nil : String(session.epoch))
  }
}

// SPEC: domain.uitool.injection
/// The CLI-side injection mechanisms. `launch` is the cooperative spawn-inject path
/// (`posix_spawn` under `DYLD_INSERT_LIBRARIES`); it needs no machine defang and no
/// debugger entitlement, so it runs on a stock Mac against your own debug builds.
enum Injection {

  struct ResolvedTarget {
    let executablePath: String
    let bundleId: String?
  }

  /// Resolve `<target>` — a `.app` path, a plain executable path, or a bundle id —
  /// to the executable to spawn. Unresolvable is `APP_NOT_FOUND` (exit 3).
  static func resolveTarget(_ target: String) throws -> ResolvedTarget {
    let fileManager = FileManager.default
    if target.hasSuffix(".app"), let bundle = Bundle(path: target),
      let executable = bundle.executablePath
    {
      return ResolvedTarget(executablePath: executable, bundleId: bundle.bundleIdentifier)
    }
    if fileManager.isExecutableFile(atPath: target) {
      return ResolvedTarget(executablePath: target, bundleId: nil)
    }
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target),
      let bundle = Bundle(url: url), let executable = bundle.executablePath
    {
      return ResolvedTarget(executablePath: executable, bundleId: target)
    }
    throw UIToolError.appNotFound("no launchable app for \(target)")
  }

  /// Spawn `executable` with the boot dylib inserted; the child is independent and
  /// survives the CLI's exit so later read verbs can connect. Its stdio is
  /// redirected to `/dev/null` so it never holds the CLI's stdout open (which would
  /// hang a `$(uitool launch …)` capture) and never pollutes the machine contract.
  static func spawnInjected(executable: String, args: [String], dylib: String) throws -> pid_t {
    var pid: pid_t = 0
    let argv: [UnsafeMutablePointer<CChar>?] = ([executable] + args).map { strdup($0) } + [nil]
    defer { for pointer in argv { free(pointer) } }

    var environment = ProcessInfo.processInfo.environment
    environment["DYLD_INSERT_LIBRARIES"] = dylib
    let envp: [UnsafeMutablePointer<CChar>?] =
      environment.map { strdup("\($0.key)=\($0.value)") } + [nil]
    defer { for pointer in envp { free(pointer) } }

    var fileActions: posix_spawn_file_actions_t?
    posix_spawn_file_actions_init(&fileActions)
    defer { posix_spawn_file_actions_destroy(&fileActions) }
    posix_spawn_file_actions_addopen(&fileActions, 0, "/dev/null", O_RDONLY, 0)
    posix_spawn_file_actions_addopen(&fileActions, 1, "/dev/null", O_WRONLY, 0)
    posix_spawn_file_actions_addopen(&fileActions, 2, "/dev/null", O_WRONLY, 0)

    let status = posix_spawn(&pid, executable, &fileActions, nil, argv, envp)
    guard status == 0 else {
      throw UIToolError.injectionFailed("posix_spawn failed (\(status)) for \(executable)")
    }
    return pid
  }

  /// Poll for the per-pid socket to appear within the bounded wait.
  static func waitForSocket(_ path: String, timeout: TimeInterval = 5) -> Bool {
    let deadline = Date().addingTimeInterval(timeout)
    while Date() < deadline {
      if FileManager.default.fileExists(atPath: path) { return true }
      usleep(50_000)  // 50 ms
    }
    return false
  }

  /// Establish the schema-checked session over the socket once it appears.
  private static func openSession(pid: pid_t, path: String, replaced: Bool) throws -> Session {
    let socketPath = UnixSocket.path(forPID: pid)
    guard waitForSocket(socketPath) else {
      throw UIToolError.injectionFailed(
        "socket never appeared for pid \(pid) within the bounded wait")
    }
    let client = try IPCClient.connect(socketPath: socketPath)
    defer { client.close() }
    let ping = try client.handshake()  // SCHEMA_MISMATCH (exit 8) on skew
    return Session(
      pid: pid, bundleId: nil, path: path, replaced: replaced, reused: false, epoch: ping.epoch)
  }

  /// Launch a target fresh under inspection (the cooperative spawn-inject path).
  static func launch(target: String, replace: Bool, args: [String]) throws -> Session {
    let resolved = try resolveTarget(target)
    let replaced = try terminateRunningIfNeeded(bundleId: resolved.bundleId, replace: replace)
    let dylib = try BootDylib.require()
    let pid = try spawnInjected(executable: resolved.executablePath, args: args, dylib: dylib)
    var session = try openSession(pid: pid, path: "launch", replaced: replaced)
    session = Session(
      pid: session.pid, bundleId: resolved.bundleId, path: session.path,
      replaced: session.replaced, reused: session.reused, epoch: session.epoch)
    return session
  }

  /// Attach to an already-running target, preserving its live state — acquire its
  /// task port and remote-`dlopen` the boot dylib (the cooperative attach-to-running
  /// path, [[domain.uitool.injection]]). Needs `uitool` signed with the debugger
  /// entitlement; no machine defang.
  static func attach(target: String) throws -> Session {
    guard let pid = SessionSnapshotSource.resolvePID(for: target), processIsAlive(pid) else {
      throw UIToolError.appNotRunning("no running process for \(target)")
    }
    let bundleId = Int32(target) == nil ? target : nil
    let socketPath = UnixSocket.path(forPID: pid)

    // Idempotent: a target already serving from this session is reused, not
    // re-injected ([[command.uitool.attach]] lifecycle).
    if let client = try? IPCClient.connect(socketPath: socketPath) {
      defer { client.close() }
      if let ping = try? client.handshake() {
        return Session(
          pid: pid, bundleId: bundleId, path: "running", replaced: false, reused: true,
          epoch: ping.epoch)
      }
    }

    let dylib = try BootDylib.require()
    let stage = RemoteInjector.inject(pid: pid, dylibPath: dylib)
    guard stage == 0 else { throw injectError(stage) }
    let session = try openSession(pid: pid, path: "running", replaced: false)
    return Session(
      pid: pid, bundleId: bundleId, path: "running", replaced: false, reused: false,
      epoch: session.epoch)
  }

  private static func processIsAlive(_ pid: pid_t) -> Bool {
    kill(pid, 0) == 0
  }

  /// Map a non-zero `uitool_inject` stage code to the closed error vocabulary. A
  /// denied `task_for_pid` is a precondition (the missing entitlement, exit 6);
  /// every other stage is an injection failure (exit 4).
  private static func injectError(_ stage: Int32) -> UIToolError {
    switch stage {
    case 1:
      return .preconditionFailed(
        "task_for_pid denied — sign uitool with com.apple.security.cs.debugger "
          + "(or run as root); see docs/uitool-dev-setup.md")
    default:
      return .injectionFailed("remote injection failed at stage \(stage)")
    }
  }

  /// For a bundle target already running: refuse without `--replace`, else
  /// terminate the running instances first. Returns whether anything was replaced.
  private static func terminateRunningIfNeeded(bundleId: String?, replace: Bool) throws -> Bool {
    guard let bundleId else { return false }
    let running = NSRunningApplication.runningApplications(withBundleIdentifier: bundleId)
    guard !running.isEmpty else { return false }
    guard replace else {
      throw UIToolError.badSelector(
        "\(bundleId) is already running — use 'uitool attach' to inspect it preserving state, "
          + "or --replace to relaunch fresh")
    }
    for application in running { application.terminate() }
    usleep(300_000)  // brief grace for the prior instance to exit
    return true
  }
}
