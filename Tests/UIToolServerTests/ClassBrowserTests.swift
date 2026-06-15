import AppKit
import Foundation
import TestSupport
import Testing
import UIToolCore

@testable import UIToolServer

// SPEC: command.uitool.classes
//
// The class browser in-process (no socket, no injection): enumerate the loaded
// classes and reflect one. Runs in the test process, which has AppKit loaded.

@Suite(.spec("command.uitool.classes"))
struct ClassBrowserTests {

  @Test(.scenario("scenario.uitool.classes-browse.list"))
  func `list finds a known loaded class by pattern`() {
    let result = ClassBrowser.list(
      pattern: "NSVisualEffectView", matches: { $0.contains("NSVisualEffectView") }, limit: 200)
    #expect(result.names.contains("NSVisualEffectView"))
    #expect(result.count >= 1)
  }

  @Test(.scenario("scenario.uitool.classes-browse.bounded"))
  func `the list is capped at the limit and reports truncated`() {
    // Match a very common prefix so there are more than the limit.
    let result = ClassBrowser.list(pattern: "NS", matches: { $0.hasPrefix("NS") }, limit: 5)
    #expect(result.names.count == 5)
    #expect(result.truncated)
    #expect(result.count > 5)
  }

  @Test(.scenario("scenario.uitool.classes-browse.reflect"))
  func `reflect a known class reports its chain and members`() {
    let info = ClassBrowser.reflect(className: "NSView")
    #expect(info.loaded)
    #expect(info.superclasses.contains("NSResponder"))
    #expect(info.superclasses.last == "NSObject")
  }

  @Test(.scenario("scenario.uitool.classes-browse.unloaded"))
  func `reflect an unloaded class is loaded false`() {
    let info = ClassBrowser.reflect(className: "NoSuchClassXYZ123")
    #expect(!info.loaded)
    #expect(info.superclasses.isEmpty)
  }
}
