import AgentCLI
import AppKit
import ArgumentParser
import Darwin
import Foundation
import Security
import UIToolCore

// SPEC: command.uitool.signing
/// `uitool signing <target>` — read a target's code signature and report the facts
/// that decide injectability, plus the derived cooperative-injectability verdict
/// ([[command.uitool.signing]]). Static and read-only: it reads the signature off
/// the binary (resolved from a pid, a bundle id, or a path), never injecting.
struct SigningCommand: ParsableCommand {
  static let configuration = CommandConfiguration(
    commandName: "signing",
    abstract: "Read a target's code signature + cooperative-injectability verdict.")

  @Argument(help: "The target: a running pid, a bundle id, or a path to a .app / executable.")
  var target: String

  @Flag(name: .customLong("pretty"), help: "Pretty-print the JSON object.")
  var pretty = false

  func run() throws {
    do {
      let report = try SigningReader.read(target: target)
      print(pretty ? try Output.json(report) : try Output.line(report))
    } catch let error as UIToolError {
      Diagnostics.fail(error)
    }
  }
}

// SPEC: command.uitool.signing
/// Resolve a target to its binary and read the signature via the Security framework.
enum SigningReader {
  /// The injection-relevant entitlement keys ([[domain.uitool.injection]]).
  private static let relevantKeys = [
    "com.apple.security.get-task-allow",
    "com.apple.security.cs.debugger",
    "com.apple.security.cs.disable-library-validation",
    "com.apple.security.cs.allow-dyld-environment-variables",
    "com.apple.security.app-sandbox",
  ]

  static func read(target: String) throws -> SigningReport {
    let path = try binaryPath(for: target)

    var code: SecStaticCode?
    guard
      SecStaticCodeCreateWithPath(URL(fileURLWithPath: path) as CFURL, [], &code) == errSecSuccess,
      let staticCode = code
    else {
      return unsigned(target: target)
    }

    var infoCF: CFDictionary?
    let flags = SecCSFlags(rawValue: kSecCSSigningInformation | kSecCSRequirementInformation)
    SecCodeCopySigningInformation(staticCode, flags, &infoCF)
    let info = (infoCF as? [String: Any]) ?? [:]

    let identifier = info[kSecCodeInfoIdentifier as String] as? String
    let teamId = info[kSecCodeInfoTeamIdentifier as String] as? String
    let entitlements = (info[kSecCodeInfoEntitlementsDict as String] as? [String: Any]) ?? [:]
    let csFlags = (info[kSecCodeInfoFlags as String] as? NSNumber)?.uint32Value ?? 0
    let hardened = (csFlags & 0x1_0000) != 0  // CS_RUNTIME
    let adhoc = (csFlags & 0x2) != 0  // CS_ADHOC
    let signed = identifier != nil

    let getTaskAllow = (entitlements["com.apple.security.get-task-allow"] as? Bool) ?? false
    let sandboxed = (entitlements["com.apple.security.app-sandbox"] as? Bool) ?? false
    let allowsDyldEnv =
      (entitlements["com.apple.security.cs.allow-dyld-environment-variables"] as? Bool) ?? false
    let disablesLibval =
      (entitlements["com.apple.security.cs.disable-library-validation"] as? Bool) ?? false

    return SigningReport(
      target: target,
      signed: signed,
      identifier: identifier,
      teamId: teamId,
      authority: !signed ? "unsigned" : (adhoc ? "ad-hoc" : (leafName(info) ?? "signed")),
      hardenedRuntime: hardened,
      sandboxed: sandboxed,
      getTaskAllow: getTaskAllow,
      entitlements: relevant(entitlements),
      cooperativeInjectable: SigningVerdict.cooperativeInjectable(
        getTaskAllow: getTaskAllow, hardenedRuntime: hardened, allowsDyldEnv: allowsDyldEnv,
        disablesLibval: disablesLibval))
  }

  /// Resolve `<target>` to an executable path: a `.app` path → its executable, a
  /// plain executable path → itself, a pid → its process binary, a bundle id → the
  /// app's executable. Unresolvable is `APP_NOT_FOUND` (exit 3).
  private static func binaryPath(for target: String) throws -> String {
    let fileManager = FileManager.default
    if target.hasSuffix(".app"), let bundle = Bundle(path: target), let exe = bundle.executablePath
    {
      return exe
    }
    if fileManager.isExecutableFile(atPath: target), !target.hasSuffix(".app") {
      return target
    }
    if let pid = Int32(target) {
      var buffer = [CChar](repeating: 0, count: 4096)
      guard proc_pidpath(pid, &buffer, UInt32(buffer.count)) > 0 else {
        throw UIToolError.appNotRunning("no process \(pid)")
      }
      return String(cString: buffer)
    }
    if let url = NSWorkspace.shared.urlForApplication(withBundleIdentifier: target),
      let bundle = Bundle(url: url), let exe = bundle.executablePath
    {
      return exe
    }
    throw UIToolError.appNotFound("no binary for \(target)")
  }

  /// The injection-relevant entitlement subset, as JSON scalars.
  private static func relevant(_ entitlements: [String: Any]) -> [String: JSONValue] {
    var result: [String: JSONValue] = [:]
    for key in relevantKeys {
      switch entitlements[key] {
      case let value as Bool: result[key] = .bool(value)
      case let value as String: result[key] = .string(value)
      default: break
      }
    }
    return result
  }

  /// The leaf certificate's common name, when the signature is real (not ad-hoc).
  private static func leafName(_ info: [String: Any]) -> String? {
    guard let certs = info[kSecCodeInfoCertificates as String] as? [SecCertificate],
      let leaf = certs.first
    else { return nil }
    var common: CFString?
    SecCertificateCopyCommonName(leaf, &common)
    return common as String?
  }

  private static func unsigned(target: String) -> SigningReport {
    SigningReport(
      target: target, signed: false, identifier: nil, teamId: nil, authority: "unsigned",
      hardenedRuntime: false, sandboxed: false, getTaskAllow: false, entitlements: [:],
      cooperativeInjectable: false)
  }
}
