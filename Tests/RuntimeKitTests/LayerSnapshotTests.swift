import AppKit
import ObjectiveC
import QuartzCore
import TestSupport
import Testing

@testable import RuntimeKit

// SPEC: domain.runtime.walker
//
// The walker oracle for the CALayer port: known layers constructed in-process
// (no injection), their decomposed fields asserted against what was set. These
// touch Core Animation / AppKit, so the suite is `@MainActor` and needs a
// logged-in (window-server) macOS session — that is expected.

// SPEC: domain.runtime.walker
@Suite(.spec("domain.runtime.walker"))
@MainActor
struct LayerSnapshotTests {

  @Test
  func `a layer with a corner radius and a sublayer reports both`() {
    let layer = CALayer()
    layer.cornerRadius = 8

    let sublayer = CALayer()
    layer.addSublayer(sublayer)

    let snapshot = LayerSnapshot.snapshot(of: layer)
    #expect(snapshot.present)
    #expect(snapshot.cornerRadius == 8)
    #expect(snapshot.sublayerCount == 1)
    #expect(snapshot.sublayers.count == 1)
    #expect(snapshot.sublayers[0].present)
    #expect(!snapshot.truncated)
  }

  @Test
  func `a nil layer is not present`() {
    let snapshot = LayerSnapshot.snapshot(of: nil)
    #expect(!snapshot.present)
    #expect(snapshot.className.isEmpty)
    #expect(snapshot.sublayerCount == 0)
    #expect(snapshot.sublayers.isEmpty)
    #expect(!snapshot.truncated)
  }

  @Test
  func `the class name is the real runtime subclass, not the static type`() {
    let layer = CALayer()
    let snapshot = LayerSnapshot.snapshot(of: layer)
    #expect(snapshot.className == NSStringFromClass(object_getClass(layer)!))
    #expect(snapshot.className == "CALayer")
  }

  @Test
  func `scalar facts are read raw off the layer`() {
    let layer = CALayer()
    layer.opacity = 0.5
    layer.borderWidth = 2
    layer.masksToBounds = true
    layer.isHidden = true
    layer.contentsScale = 2
    layer.shadowOpacity = 0.25
    layer.shadowRadius = 4
    layer.shadowOffset = CGSize(width: 3, height: -5)
    layer.maskedCorners = [.layerMinXMinYCorner, .layerMaxXMaxYCorner]

    let snapshot = LayerSnapshot.snapshot(of: layer)
    #expect(snapshot.opacity == 0.5)
    #expect(snapshot.borderWidth == 2)
    #expect(snapshot.masksToBounds)
    #expect(snapshot.isHidden)
    #expect(snapshot.contentsScale == 2)
    #expect(snapshot.shadowOpacity == 0.25)
    #expect(snapshot.shadowRadius == 4)
    #expect(snapshot.shadowOffsetWidth == 3)
    #expect(snapshot.shadowOffsetHeight == -5)
    #expect(
      snapshot.maskedCorners
        == CACornerMask([.layerMinXMinYCorner, .layerMaxXMaxYCorner]).rawValue)
  }

  @Test
  func `a layer background color flattens to its sRGB hex`() {
    let layer = CALayer()
    layer.backgroundColor = CGColor(srgbRed: 1, green: 0, blue: 0, alpha: 1)
    let snapshot = LayerSnapshot.snapshot(of: layer)
    #expect(snapshot.backgroundColor == "#FF0000FF")
  }

  @Test(.scenario("scenario.runtime.walker.layer-defaults"))
  func `a default layer reports CALayer's real color defaults`() {
    let layer = CALayer()
    let snapshot = LayerSnapshot.snapshot(of: layer)
    // CALayer initializes backgroundColor to nil but borderColor and shadowColor
    // to opaque black — the walker reports the real CGColor, not a synthesized nil.
    #expect(snapshot.backgroundColor == nil)
    #expect(snapshot.borderColor == "#000000FF")
    #expect(snapshot.shadowColor == "#000000FF")
  }

  @Test
  func `the snapshot serializes to JSON off the structure alone`() throws {
    let layer = CALayer()
    layer.cornerRadius = 8
    let snapshot = LayerSnapshot.snapshot(of: layer)
    let data = try JSONEncoder().encode(snapshot)
    let decoded = try JSONDecoder().decode(LayerSnapshot.self, from: data)
    #expect(decoded.cornerRadius == 8)
    #expect(decoded.present)
  }

  @Test(.scenario("scenario.runtime.walker.layer-depth"))
  func `the depth bound truncates a deep tree while still counting its sublayers`() {
    // root -> child -> grandchild. A maxDepth of 1 admits the root's direct
    // sublayer (depth budget 1 -> 0) but truncates AT the child, which still has a
    // grandchild: its sublayers are omitted, yet its sublayerCount stays truthful.
    let root = CALayer()
    let child = CALayer()
    let grandchild = CALayer()
    child.addSublayer(grandchild)
    root.addSublayer(child)

    let snapshot = LayerSnapshot.snapshot(of: root, maxDepth: 1)
    #expect(snapshot.present)
    #expect(!snapshot.truncated)
    #expect(snapshot.sublayers.count == 1)

    let childSnapshot = snapshot.sublayers[0]
    #expect(childSnapshot.truncated)
    #expect(childSnapshot.sublayerCount == 1)
    #expect(childSnapshot.sublayers.isEmpty)
  }

  @Test(.scenario("scenario.runtime.walker.layer-depth"))
  func `a zero depth bound truncates a root that has sublayers`() {
    let root = CALayer()
    root.addSublayer(CALayer())
    let snapshot = LayerSnapshot.snapshot(of: root, maxDepth: 0)
    #expect(snapshot.truncated)
    #expect(snapshot.sublayerCount == 1)
    #expect(snapshot.sublayers.isEmpty)
  }

  @Test
  func `a leaf at the depth floor is not marked truncated`() {
    // A layer with no sublayers at depth 0 has nothing to omit, so it is not
    // truncated — truncation means "sublayers were dropped", not "depth reached".
    let snapshot = LayerSnapshot.snapshot(of: CALayer(), maxDepth: 0)
    #expect(!snapshot.truncated)
    #expect(snapshot.sublayerCount == 0)
  }
}
