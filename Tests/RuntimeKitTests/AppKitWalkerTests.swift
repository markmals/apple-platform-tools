import AppKit
import Foundation
import ObjectiveC
import TestSupport
import Testing

@testable import RuntimeKit

// SPEC: domain.runtime.walker
//
// The walker oracle: a known NSView tree built in-process on the main thread (no
// injection), placed in an NSWindow's contentView, snapshotted by AppKitWalker,
// and asserted against what was constructed. The decomposition pins the real
// runtime class of each node (object_getClass, not the static type), the raw
// bottom-left frame AND the normalized top-left frame AND isFlipped (the
// coordinate flip), childCount/children, a text view's font snapshot, an
// NSVisualEffectView's material, depth truncation, the SwiftUI boundary flag, and
// Sendable/Codable round-tripping. These touch AppKit, so the suite is
// `@MainActor` and needs a logged-in (window-server) macOS session — expected for
// the walker layer.

// A flipped container so the flip path through AppKit's own conversions is
// exercised by a real isFlipped == true node, not only the default bottom-left.
private final class FlippedView: NSView {
  override var isFlipped: Bool { true }
}

// SPEC: domain.runtime.walker
@Suite(.spec("domain.runtime.walker"))
@MainActor
struct AppKitWalkerTests {

  /// A 400×300 borderless window with a known contentView, off-screen so the
  /// suite never steals focus. The window is returned alongside its contentView so
  /// callers can drive the walker against a real window for the flip math.
  private func makeWindow(contentSize: CGSize = CGSize(width: 400, height: 300)) -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: contentSize),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false)
    return window
  }

  @Test(.scenario("scenario.runtime.walker.real-class"))
  func `the snapshot reports each node's real runtime class, not the static type`() {
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
    let label = NSTextField(labelWithString: "Hello")
    let effect = NSVisualEffectView(frame: NSRect(x: 10, y: 20, width: 80, height: 40))
    parent.addSubview(label)
    parent.addSubview(effect)

    let window = makeWindow()
    window.contentView = parent

    let snapshot = AppKitWalker.snapshot(view: parent, inWindow: window)

    #expect(snapshot.runtimeClass == NSStringFromClass(object_getClass(parent)!))
    let childClasses = snapshot.children.map(\.runtimeClass)
    #expect(childClasses.contains("NSTextField"))
    #expect(childClasses.contains("NSVisualEffectView"))
  }

  @Test
  func `childCount and the children array reflect the subview tree in z-order`() {
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
    let first = NSTextField(labelWithString: "first")
    let second = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 10, height: 10))
    parent.addSubview(first)
    parent.addSubview(second)

    let snapshot = AppKitWalker.snapshot(view: parent, inWindow: makeWindow())

    #expect(snapshot.childCount == 2)
    #expect(snapshot.children.count == 2)
    // z-order: subviews are back-to-front, so the array order is the add order.
    #expect(snapshot.children[0].runtimeClass == "NSTextField")
    #expect(snapshot.children[1].runtimeClass == "NSVisualEffectView")
    #expect(!snapshot.truncated)
  }

  @Test(.scenario("scenario.runtime.walker.coordinate-flip"))
  func `the raw frame is bottom-left and frameTopLeft is the normalized top-left flip`() {
    // Two stacked subviews in a non-flipped parent. In AppKit's bottom-left
    // origin, the LOWER-on-screen view has the SMALLER frame.origin.y. When
    // normalized to a top-left origin, that ordering inverts: the lower-on-screen
    // view has the LARGER frameTopLeft.y. Asserting the inversion proves the flip
    // happened (rather than pinning a titlebar-dependent magic number).
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let lower = NSView(frame: NSRect(x: 5, y: 10, width: 50, height: 50))
    let upper = NSView(frame: NSRect(x: 5, y: 200, width: 50, height: 50))
    parent.addSubview(lower)
    parent.addSubview(upper)

    let window = makeWindow()
    window.contentView = parent

    let snapshot = AppKitWalker.snapshot(view: parent, inWindow: window)
    let lowerSnap = snapshot.children[0]
    let upperSnap = snapshot.children[1]

    // The raw frame is carried verbatim, bottom-left origin.
    #expect(lowerSnap.frame.x == 5)
    #expect(lowerSnap.frame.y == 10)
    #expect(lowerSnap.frame.width == 50)
    #expect(lowerSnap.frame.height == 50)

    // x is unaffected by the vertical flip.
    #expect(lowerSnap.frameTopLeft.x == 5)
    #expect(lowerSnap.frameTopLeft.width == 50)
    #expect(lowerSnap.frameTopLeft.height == 50)

    // The flip inverts the vertical ordering: bottom-left y(lower) < y(upper),
    // top-left y(lower) > y(upper).
    #expect(lowerSnap.frame.y < upperSnap.frame.y)
    #expect(lowerSnap.frameTopLeft.y > upperSnap.frameTopLeft.y)

    // A non-flipped NSView reports isFlipped == false; the normalization handled
    // the flip without the view itself being flipped.
    #expect(!lowerSnap.isFlipped)
  }

  @Test(.scenario("scenario.runtime.walker.coordinate-flip"))
  func `a flipped view reports isFlipped and still normalizes to a top-left frame`() {
    let parent = FlippedView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let child = NSView(frame: NSRect(x: 7, y: 30, width: 40, height: 20))
    parent.addSubview(child)

    let window = makeWindow()
    window.contentView = parent

    let snapshot = AppKitWalker.snapshot(view: parent, inWindow: window)
    #expect(snapshot.isFlipped)
    // The child's normalized rect is computed through AppKit's own conversions, so
    // a flipped parent does not double-flip: width/height survive intact and x is
    // unchanged.
    let childSnap = snapshot.children[0]
    #expect(childSnap.frameTopLeft.x == 7)
    #expect(childSnap.frameTopLeft.width == 40)
    #expect(childSnap.frameTopLeft.height == 20)
  }

  @Test(.scenario("scenario.runtime.walker.coordinate-flip"))
  func `with no window frameTopLeft falls back to the raw frame`() {
    let view = NSView(frame: NSRect(x: 11, y: 22, width: 33, height: 44))
    let snapshot = AppKitWalker.snapshot(view: view, inWindow: nil)
    #expect(snapshot.frameTopLeft.x == snapshot.frame.x)
    #expect(snapshot.frameTopLeft.y == snapshot.frame.y)
    #expect(snapshot.frameTopLeft.width == snapshot.frame.width)
    #expect(snapshot.frameTopLeft.height == snapshot.frame.height)
  }

  @Test
  func `a text field surfaces its decomposed font and its text`() throws {
    let label = NSTextField(labelWithString: "Greetings")
    label.font = NSFont.systemFont(ofSize: 18, weight: .bold)
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    parent.addSubview(label)

    let snapshot = AppKitWalker.snapshot(view: parent, inWindow: makeWindow())
    let labelSnap = try #require(snapshot.children.first { $0.runtimeClass == "NSTextField" })

    let font = try #require(labelSnap.font, "a text field carries a font snapshot")
    #expect(font.size == 18)
    #expect(font.weightName == "bold")
    #expect(labelSnap.text == "Greetings")
  }

  @Test
  func `an NSVisualEffectView reports its material and blending mode`() throws {
    let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 60, height: 60))
    effect.material = .sidebar
    effect.blendingMode = .behindWindow
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    parent.addSubview(effect)

    let snapshot = AppKitWalker.snapshot(view: parent, inWindow: makeWindow())
    let effectSnap = try #require(
      snapshot.children.first { $0.runtimeClass == "NSVisualEffectView" })

    #expect(effectSnap.material == "sidebar")
    #expect(effectSnap.blendingMode == "behindWindow")
  }

  @Test
  func `a plain view carries no material`() {
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    parent.addSubview(NSView(frame: .zero))
    let snapshot = AppKitWalker.snapshot(view: parent, inWindow: makeWindow())
    #expect(snapshot.material == nil)
    #expect(snapshot.blendingMode == nil)
  }

  @Test(.scenario("scenario.runtime.walker.depth-truncation"))
  func `the depth bound truncates a deep tree while still counting its subviews`() {
    // parent -> child -> grandchild. maxDepth 1 admits the parent's direct child
    // (depth 0 -> 1) but truncates AT the child, which still has a grandchild: its
    // children are omitted, yet childCount stays truthful.
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: 100, height: 100))
    let child = NSView(frame: NSRect(x: 0, y: 0, width: 50, height: 50))
    let grandchild = NSView(frame: NSRect(x: 0, y: 0, width: 25, height: 25))
    child.addSubview(grandchild)
    parent.addSubview(child)

    let snapshot = AppKitWalker.snapshot(view: parent, inWindow: makeWindow(), maxDepth: 1)
    #expect(!snapshot.truncated)
    #expect(snapshot.children.count == 1)

    let childSnap = snapshot.children[0]
    #expect(childSnap.truncated)
    #expect(childSnap.childCount == 1)
    #expect(childSnap.children.isEmpty)
  }

  @Test
  func `a leaf at the depth floor is not marked truncated`() {
    // A view with no subviews at the bound has nothing to omit.
    let snapshot = AppKitWalker.snapshot(
      view: NSView(frame: .zero), inWindow: makeWindow(), maxDepth: 0)
    #expect(!snapshot.truncated)
    #expect(snapshot.childCount == 0)
  }

  @Test
  func `the superclass chain runs up to NSObject`() {
    let snapshot = AppKitWalker.snapshot(view: NSTextField(labelWithString: "x"), inWindow: nil)
    // NSTextField -> NSControl -> NSView -> NSResponder -> NSObject. The chain is
    // exclusive of the node's own class (runtimeClass) and inclusive of NSObject.
    #expect(!snapshot.superclasses.contains(snapshot.runtimeClass))
    #expect(snapshot.superclasses.contains("NSControl"))
    #expect(snapshot.superclasses.contains("NSView"))
    #expect(snapshot.superclasses.last == "NSObject")
  }

  @Test(.scenario("scenario.runtime.walker.swiftui-boundary"))
  func `a plain AppKit view is not a SwiftUI boundary`() {
    let snapshot = AppKitWalker.snapshot(view: NSView(frame: .zero), inWindow: nil)
    #expect(!snapshot.swiftUIBoundary)
  }

  @Test
  func `a layer-backed view surfaces its layer snapshot`() throws {
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
    view.wantsLayer = true
    view.layer?.cornerRadius = 6

    let snapshot = AppKitWalker.snapshot(view: view, inWindow: nil)
    let layer = try #require(snapshot.layer, "a layer-backed view carries a layer snapshot")
    #expect(layer.present)
    #expect(layer.cornerRadius == 6)
  }

  @Test(.scenario("scenario.runtime.walker.unbacked-layer"))
  func `a view with no backing layer carries no layer snapshot`() {
    // wantsLayer defaults to false, so view.layer is nil — the field is absent,
    // not a present:false stand-in.
    let view = NSView(frame: NSRect(x: 0, y: 0, width: 40, height: 40))
    let snapshot = AppKitWalker.snapshot(view: view, inWindow: nil)
    #expect(snapshot.layer == nil)
  }

  @Test(.scenario("scenario.runtime.walker.child-window-nesting"))
  func `an attached child window is nested under its parent, not dropped`() throws {
    let parent = makeWindow()
    parent.title = "Parent Window"
    parent.makeKeyAndOrderFront(nil)
    let child = makeWindow(contentSize: CGSize(width: 200, height: 150))
    child.title = "Child Window"
    parent.addChildWindow(child, ordered: .above)
    defer {
      parent.removeChildWindow(child)
      child.orderOut(nil)
      parent.orderOut(nil)
    }

    let windows = AppKitWalker.snapshotApplicationWindows()
    let parentSnap = try #require(windows.first { $0.title == "Parent Window" })
    // The child has a parent, so it is not a top-level root — it appears only
    // nested under the parent rather than being dropped.
    #expect(!windows.contains { $0.title == "Child Window" })
    #expect(parentSnap.childWindows.contains { $0.title == "Child Window" })
  }

  @Test
  func `a view's constraint node is composed into its snapshot`() throws {
    let view = NSView(frame: .zero)
    view.widthAnchor.constraint(equalToConstant: 120).isActive = true
    let snapshot = AppKitWalker.snapshot(view: view, inWindow: nil)
    let constraints = try #require(snapshot.constraints)
    let width = try #require(constraints.constraints.first { $0.first.attribute == "width" })
    #expect(width.constant == 120)
  }

  @Test
  func `snapshotApplicationWindows finds a window placed on screen`() throws {
    let window = makeWindow()
    window.title = "Walker Test Window"
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    parent.addSubview(NSTextField(labelWithString: "in window"))
    window.contentView = parent
    window.makeKeyAndOrderFront(nil)
    defer { window.orderOut(nil) }

    let windows = AppKitWalker.snapshotApplicationWindows()
    let snap = try #require(
      windows.first { $0.title == "Walker Test Window" },
      "the ordered-front window must appear among the application windows")

    #expect(snap.runtimeClass == NSStringFromClass(object_getClass(window)!))
    // The window server settles an on-screen frame below display precision between
    // the walk and this read, so compare geometry within a sub-point tolerance.
    #expect(abs(snap.frame.width - Double(window.frame.width)) < 1)
    #expect(abs(snap.frame.height - Double(window.frame.height)) < 1)
    let content = try #require(snap.contentView)
    #expect(content.childCount == 1)
  }

  @Test
  func `hit testing returns the deepest view at a point`() throws {
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: 400, height: 300))
    let target = NSVisualEffectView(frame: NSRect(x: 50, y: 50, width: 100, height: 100))
    parent.addSubview(target)
    let window = makeWindow()
    window.contentView = parent

    // A point inside the target, in window base (bottom-left) coordinates. The
    // contentView is offset below the titlebar, so convert the content-relative
    // point into window base coordinates the way hitTest expects.
    let contentPoint = NSPoint(x: 100, y: 100)
    let windowPoint = parent.convert(contentPoint, to: nil)

    let hit = try #require(AppKitWalker.snapshotForHitTest(at: windowPoint, inWindow: window))
    // The deepest hit at that point is the effect view (or one of its descendants
    // that still reports the effect view's class in its chain); the effect view is
    // the front-most subview covering the point.
    #expect(
      hit.runtimeClass == "NSVisualEffectView" || hit.superclasses.contains("NSVisualEffectView"))
    // A hit-test node is captured as a single node with children omitted.
    #expect(hit.children.isEmpty)
  }

  @Test
  func `the snapshot is Sendable and round-trips through JSON`() async throws {
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
    let label = NSTextField(labelWithString: "encode me")
    label.font = NSFont.systemFont(ofSize: 14, weight: .regular)
    let effect = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 30, height: 30))
    effect.material = .menu
    parent.addSubview(label)
    parent.addSubview(effect)

    let window = makeWindow()
    window.contentView = parent
    let snapshot = AppKitWalker.snapshot(view: parent, inWindow: window)

    // A genuinely Sendable value crosses an actor hop. The snapshot holds no
    // NSView, so this compiles and runs off the main actor.
    let encoded = try await Task.detached { () -> Data in
      try JSONEncoder().encode(snapshot)
    }.value
    let decoded = try JSONDecoder().decode(ViewSnapshot.self, from: encoded)

    #expect(decoded.runtimeClass == snapshot.runtimeClass)
    #expect(decoded.childCount == snapshot.childCount)
    #expect(decoded.children.count == snapshot.children.count)
    let decodedLabel = try #require(decoded.children.first { $0.runtimeClass == "NSTextField" })
    #expect(decodedLabel.text == "encode me")
    #expect(decodedLabel.font?.size == 14)
    let decodedEffect = try #require(
      decoded.children.first { $0.runtimeClass == "NSVisualEffectView" })
    #expect(decodedEffect.material == "menu")
  }
}
