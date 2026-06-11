import TestSupport
import Testing

@testable import RedumpCore

@Suite(.spec("command.redump.backends"))
struct DisassemblerTests {
  @Test func `resolves a backend from its environment override`() {
    let path = BackendDetector.resolve(
      .ida, environment: ["RE_IDAT64": "/opt/idat64"], exists: { _ in false })
    #expect(path == "/opt/idat64")
  }

  @Test func `resolves a backend from a known install path`() {
    let hopper = "/Applications/Hopper.app/Contents/MacOS/hopper"
    let path = BackendDetector.resolve(.hopper, environment: [:], exists: { $0 == hopper })
    #expect(path == hopper)
  }

  @Test func `reports every backend as unconfigured when nothing is found`() {
    let statuses = BackendDetector.detect(environment: [:], exists: { _ in false })
    #expect(statuses.count == 2)
    #expect(statuses.allSatisfy { !$0.configured && $0.path == nil })
  }

  @Test func `marks a configured backend with its resolved path`() {
    let statuses = BackendDetector.detect(
      environment: ["RE_HOPPER": "/x/hopper"], exists: { _ in false })
    let hopper = statuses.first { $0.backend == "hopper" }
    #expect(hopper?.configured == true)
    #expect(hopper?.path == "/x/hopper")
  }
}
