import Foundation
import TestSupport
import Testing

@testable import uitool

// SPEC: command.uitool.classes
//
// The classes surface — its two modes parse, and neither mode is rejected at run.

@Suite(.spec("command.uitool.classes"))
struct ClassesSurfaceTests {

  @Test func `the classes surface parses the list mode`() throws {
    let command = try ClassesCommand.parse(["4821", "--match", "NSVisual", "--limit", "50"])
    #expect(command.app == "4821")
    #expect(command.match == "NSVisual")
    #expect(command.className == nil)
    #expect(command.limit == 50)
  }

  @Test func `the classes surface parses the reflect mode`() throws {
    let command = try ClassesCommand.parse(["com.example.App", "--class", "NSView"])
    #expect(command.className == "NSView")
    #expect(command.match == nil)
  }
}
