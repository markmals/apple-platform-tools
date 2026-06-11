import Foundation
import TestSupport
import Testing

@testable import AgentCLI

@Suite(.spec("domain.agent-cli"))
struct AgentCLITests {
  struct Sample: Encodable {
    let b: Int
    let a: String
    let url: String
  }

  @Test(.scenario("scenario.agent-cli.sorted-keys"))
  func `object keys are emitted in sorted order`() throws {
    let json = try Output.json(Sample(b: 1, a: "x", url: "http://e/x"))
    let a = try #require(json.range(of: "\"a\""))
    let b = try #require(json.range(of: "\"b\""))
    #expect(a.lowerBound < b.lowerBound)
  }

  @Test(.scenario("scenario.agent-cli.no-escape"))
  func `forward slashes are not escaped`() throws {
    let json = try Output.json(Sample(b: 1, a: "x", url: "http://example/path"))
    #expect(json.contains("http://example/path"))
    #expect(!json.contains("\\/"))
  }

  @Test(.scenario("scenario.agent-cli.deterministic"))
  func `equal input encodes byte-identically`() throws {
    let value = Sample(b: 1, a: "x", url: "/a/b")
    #expect(try Output.json(value) == (try Output.json(value)))
  }

  @Test(.scenario("scenario.agent-cli.jsonlines"))
  func `a stream record is one compact object per line`() throws {
    let line = try Output.line(Sample(b: 1, a: "x", url: "/a"))
    #expect(!line.contains("\n"))
    #expect(!line.contains(": "))  // compact: no pretty-printed spacing
  }

  @Test(.scenario("scenario.agent-cli.stable-float"))
  func `float rounding is stable to the requested places`() {
    #expect(stableRounded(0.1 + 0.2, places: 3) == 0.3)
    #expect(stableRounded(1.23456, places: 2) == 1.23)
  }

  @Test(.scenario("scenario.agent-cli.exit-taxonomy"))
  func `success is 0 and usage is 2`() {
    #expect(ExitStatus.success == 0)
    #expect(ExitStatus.usage == 2)
  }
}
