import Foundation
import Testing

@testable import AgentCLI

@Suite("domain.agent-cli")
struct AgentCLITests {
  struct Sample: Encodable {
    let b: Int
    let a: String
    let url: String
  }

  @Test("[scenario.agent-cli.sorted-keys] object keys are emitted in sorted order")
  func sortedKeys() throws {
    let json = try Output.json(Sample(b: 1, a: "x", url: "http://e/x"))
    let a = try #require(json.range(of: "\"a\""))
    let b = try #require(json.range(of: "\"b\""))
    #expect(a.lowerBound < b.lowerBound)
  }

  @Test("[scenario.agent-cli.no-escape] forward slashes are not escaped")
  func slashesUnescaped() throws {
    let json = try Output.json(Sample(b: 1, a: "x", url: "http://example/path"))
    #expect(json.contains("http://example/path"))
    #expect(!json.contains("\\/"))
  }

  @Test("[scenario.agent-cli.deterministic] equal input encodes byte-identically")
  func deterministic() throws {
    let value = Sample(b: 1, a: "x", url: "/a/b")
    #expect(try Output.json(value) == (try Output.json(value)))
  }

  @Test("[scenario.agent-cli.jsonlines] a stream record is one compact object per line")
  func jsonLines() throws {
    let line = try Output.line(Sample(b: 1, a: "x", url: "/a"))
    #expect(!line.contains("\n"))
    #expect(!line.contains(": "))  // compact: no pretty-printed spacing
  }

  @Test("[scenario.agent-cli.stable-float] float rounding is stable to the requested places")
  func stableFloat() {
    #expect(stableRounded(0.1 + 0.2, places: 3) == 0.3)
    #expect(stableRounded(1.23456, places: 2) == 1.23)
  }

  @Test("[scenario.agent-cli.exit-taxonomy] success is 0 and usage is 2")
  func exitTaxonomy() {
    #expect(ExitStatus.success == 0)
    #expect(ExitStatus.usage == 2)
  }
}
