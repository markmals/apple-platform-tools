import Foundation
import ObjectiveC
import TestSupport
import Testing

@testable import RuntimeKit

// SPEC: domain.runtime.reflection
@Suite(.spec("domain.runtime.reflection"))
struct RuntimeSafetyTests {

  // MARK: - Classes

  @Test(.scenario("scenario.runtime.safety.class-rejected"))
  func `every known-unsafe class name is rejected when the class is loaded`() throws {
    // Reflect the real class behind each denylisted name (when it is loaded in
    // this process) and confirm classIsSafe rejects it. Names that resolve to no
    // loaded class are asserted against the name set directly, since classIsSafe
    // takes a non-nil AnyClass.
    var checkedALoadedClass = false
    for name in RuntimeSafety.knownUnsafeClassNames {
      if let cls = NSClassFromString(name) {
        #expect(!RuntimeSafety.classIsSafe(cls), "\(name) should be unsafe")
        checkedALoadedClass = true
      }
      #expect(RuntimeSafety.knownUnsafeClassNames.contains(name))
    }
    #expect(checkedALoadedClass, "expected at least one denylisted class to be loaded")
  }

  @Test(.scenario("scenario.runtime.safety.class-rejected"))
  func `the denylist carries exactly FLEX's nineteen class entries`() {
    // Fidelity guard: the count and contents are carried verbatim from FLEX's
    // kFLEXKnownUnsafeClassCount == 19.
    #expect(RuntimeSafety.knownUnsafeClassNames.count == 19)
    for name in [
      "__ARCLite__", "__NSCFCalendar", "__NSCFTimer", "NSCFTimer",
      "__NSGenericDeallocHandler", "NSAutoreleasePool", "NSPlaceholderNumber",
      "NSPlaceholderString", "NSPlaceholderValue", "Object", "VMUArchitecture",
      "JSExport", "__NSAtom", "_NSZombie_", "_CNZombie_", "__NSMessage",
      "__NSMessageBuilder", "FigIrisAutoTrimmerMotionSampleExport", "_UIPointVector",
    ] {
      #expect(RuntimeSafety.knownUnsafeClassNames.contains(name), "missing \(name)")
    }
  }

  @Test(.scenario("scenario.runtime.safety.class-allowed"))
  func `an ordinary class is safe`() {
    // A plain non-denylisted class with a normal superclass chain.
    #expect(RuntimeSafety.classIsSafe(NSString.self))
    #expect(RuntimeSafety.classIsSafe(NSArray.self))
    #expect(RuntimeSafety.classIsSafe(RKSafetyFixture.self))
  }

  @Test(.scenario("scenario.runtime.safety.class-allowed"))
  func `the two known root classes are safe`() {
    // NSObject and NSProxy have no superclass but are the sanctioned roots.
    #expect(class_getSuperclass(NSObject.self) == nil)
    #expect(class_getSuperclass(NSProxy.self) == nil)
    #expect(RuntimeSafety.classIsSafe(NSObject.self))
    #expect(RuntimeSafety.classIsSafe(NSProxy.self))
  }

  @Test(.scenario("scenario.runtime.safety.root-class"))
  func `a root class other than NSObject or NSProxy is rejected`() throws {
    // A genuine root class (nil superclass) that is neither sanctioned root is
    // built deterministically with objc_allocateClassPair(nil, ...).
    let name = "RKUnsanctionedRoot_\(UUID().uuidString.prefix(8))"
    let root = try #require(objc_allocateClassPair(nil, name, 0))
    objc_registerClassPair(root)
    #expect(class_getSuperclass(root) == nil)
    #expect(!RuntimeSafety.classIsSafe(root), "an unsanctioned root class must be unsafe")
  }

  // MARK: - Ivars

  @Test(.scenario("scenario.runtime.safety.ivar-rejected"))
  func `the known-unsafe NSURL ivars are rejected`() {
    #expect(!RuntimeSafety.ivarIsSafe("_urlString", on: NSURL.self))
    #expect(!RuntimeSafety.ivarIsSafe("_baseURL", on: NSURL.self))
  }

  @Test(.scenario("scenario.runtime.safety.ivar-rejected"))
  func `an unsafe ivar stays unsafe on a subclass that inherits it`() {
    // FLEX keys the denylist on the Ivar identity; the name-based port walks the
    // superclass chain, so a subclass of NSURL inherits the rejection.
    final class RKURLSubclass: NSURL {}
    #expect(!RuntimeSafety.ivarIsSafe("_urlString", on: RKURLSubclass.self))
    #expect(!RuntimeSafety.ivarIsSafe("_baseURL", on: RKURLSubclass.self))
  }

  @Test(.scenario("scenario.runtime.safety.ivar-allowed"))
  func `an ordinary ivar is safe`() {
    // A normal ivar on NSURL, and any ivar on an unrelated class, are safe.
    #expect(RuntimeSafety.ivarIsSafe("_count", on: NSArray.self))
    #expect(RuntimeSafety.ivarIsSafe("anything", on: RKSafetyFixture.self))
  }

  @Test(.scenario("scenario.runtime.safety.ivar-allowed"))
  func `the NSURL unsafe ivar names are safe on an unrelated class`() {
    // The denylist is keyed on (class, name) — the same name on another class is
    // not rejected.
    #expect(RuntimeSafety.ivarIsSafe("_urlString", on: NSString.self))
    #expect(RuntimeSafety.ivarIsSafe("_baseURL", on: RKSafetyFixture.self))
  }
}

// SPEC: manual
/// An ordinary in-process class used as the "safe" oracle — neither denylisted
/// nor a root class.
@objc(RKSafetyFixture) private final class RKSafetyFixture: NSObject {}
