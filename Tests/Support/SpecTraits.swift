import Testing

// SPEC: manual
// Test-association traits, shared by every test target. `.spec(_:)` binds a suite
// (or test) to the spec ID it verifies; `.scenario(_:)` binds a test to the
// Gherkin scenario sub-ID it pins. The dotted IDs are carried verbatim so
// drift/coverage tooling can grep `.spec("…")` / `.scenario("…")`.
// See Specs/CONVENTIONS.md → "Tests carry the same IDs".

/// Associates a suite or test with the spec ID it verifies, e.g. `.spec("domain.agent-cli")`.
public struct SpecTrait: TestTrait, SuiteTrait {
  public let id: String
}

/// Associates a test with the Gherkin scenario sub-ID it pins,
/// e.g. `.scenario("scenario.agent-cli.sorted-keys")`.
public struct ScenarioTrait: TestTrait {
  public let id: String
}

extension Trait where Self == SpecTrait {
  /// `.spec("domain.agent-cli")`
  public static func spec(_ id: String) -> Self { SpecTrait(id: id) }
}

extension Trait where Self == ScenarioTrait {
  /// `.scenario("scenario.agent-cli.sorted-keys")`
  public static func scenario(_ id: String) -> Self { ScenarioTrait(id: id) }
}
