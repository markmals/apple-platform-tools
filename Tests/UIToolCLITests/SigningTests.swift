import Foundation
import TestSupport
import Testing
import UIToolCore

@testable import uitool

// SPEC: command.uitool.signing
//
// The signing surface + the Security-framework reader against real binaries on
// disk (no injection). /bin/ls is a reliably-signed Apple platform binary with no
// get-task-allow, so the read and the verdict are deterministic.

@Suite(.spec("command.uitool.signing"))
struct SigningTests {

  @Test func `the signing surface parses its target and flag`() throws {
    let command = try SigningCommand.parse(["com.apple.mail", "--pretty"])
    #expect(command.target == "com.apple.mail")
    #expect(command.pretty)
  }

  @Test func `it reads a real signed system binary as signed but not cooperatively injectable`()
    throws
  {
    let report = try SigningReader.read(target: "/bin/ls")
    #expect(report.signed)
    #expect(report.identifier != nil)
    #expect(!report.getTaskAllow)
    #expect(!report.cooperativeInjectable)  // a platform binary carries no get-task-allow
  }

  @Test func `an unresolvable target is APP_NOT_FOUND (exit 3)`() {
    do {
      _ = try SigningReader.read(target: "/no/such/binary/here")
      Issue.record("expected APP_NOT_FOUND")
    } catch let error as UIToolError {
      #expect(error.code == "APP_NOT_FOUND")
      #expect(error.exitCode == 3)
    } catch {
      Issue.record("unexpected error: \(error)")
    }
  }
}
