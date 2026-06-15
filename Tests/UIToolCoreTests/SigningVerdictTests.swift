import TestSupport
import Testing

@testable import UIToolCore

// SPEC: command.uitool.signing
//
// The cooperative-injectability verdict is pure, so it is pinned here without the
// Security framework — Posture 1 ([[domain.uitool.injection]]).

@Suite(.spec("command.uitool.signing"))
struct SigningVerdictTests {

  @Test(.scenario("scenario.uitool.signing-read.cooperative"))
  func `get-task-allow without a hardened runtime is cooperatively injectable`() {
    #expect(
      SigningVerdict.cooperativeInjectable(
        getTaskAllow: true, hardenedRuntime: false, allowsDyldEnv: false, disablesLibval: false))
  }

  @Test(.scenario("scenario.uitool.signing-read.not-cooperative"))
  func `without get-task-allow it is never cooperatively injectable`() {
    #expect(
      !SigningVerdict.cooperativeInjectable(
        getTaskAllow: false, hardenedRuntime: false, allowsDyldEnv: true, disablesLibval: true))
  }

  @Test func `a hardened runtime needs both the dyld-env and libval overrides`() {
    // Hardened + neither override → no.
    #expect(
      !SigningVerdict.cooperativeInjectable(
        getTaskAllow: true, hardenedRuntime: true, allowsDyldEnv: false, disablesLibval: false))
    // Hardened + only one override → still no.
    #expect(
      !SigningVerdict.cooperativeInjectable(
        getTaskAllow: true, hardenedRuntime: true, allowsDyldEnv: true, disablesLibval: false))
    // Hardened + both overrides → yes.
    #expect(
      SigningVerdict.cooperativeInjectable(
        getTaskAllow: true, hardenedRuntime: true, allowsDyldEnv: true, disablesLibval: true))
  }
}
