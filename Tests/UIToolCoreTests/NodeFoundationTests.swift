import Foundation
import RuntimeKit
import TestSupport
import Testing

@testable import UIToolCore

// SPEC: domain.uitool.node
//
// The pure-projection oracle: synthetic ViewSnapshot/WindowSnapshot VALUES built
// directly via their public inits (no AppKit, no window server, no injection),
// fed to UIToolCore, and asserted against the projected Node / node-id / resolve
// behavior. This is the purity boundary — the core is pure over snapshot values;
// nothing here touches a live view. A little known tree (a window whose content
// view has two same-class children and one other) exercises ids, ordinals,
// rounding, the default field set, and round-tripping.

// MARK: - Synthetic snapshot builders (no AppKit)

/// A leaf `ViewSnapshot` with sensible defaults; only the facets a test cares
/// about are overridden, so the construction reads as "an NSTextField at this
/// frame" rather than 19 positional args.
private func view(
  _ runtimeClass: String,
  frame: Rect = Rect(x: 0, y: 0, width: 10, height: 10),
  alpha: Double = 1,
  text: String? = nil,
  font: FontSnapshot? = nil,
  material: String? = nil,
  blendingMode: String? = nil,
  layer: LayerSnapshot? = nil,
  constraints: ConstraintNode? = nil,
  superclasses: [String] = ["NSView", "NSObject"],
  swiftUIBoundary: Bool = false,
  children: [ViewSnapshot] = []
) -> ViewSnapshot {
  ViewSnapshot(
    runtimeClass: runtimeClass,
    superclasses: superclasses,
    frame: frame,
    frameTopLeft: frame,
    isFlipped: false,
    hidden: false,
    alpha: alpha,
    identifier: nil,
    text: text,
    axRole: nil,
    font: font,
    material: material,
    blendingMode: blendingMode,
    layer: layer,
    constraints: constraints,
    swiftUIBoundary: swiftUIBoundary,
    childCount: children.count,
    truncated: false,
    children: children)
}

/// A window wrapping a content view — the forest root the tree walk seeds from.
private func window(_ runtimeClass: String = "NSWindow", contentView: ViewSnapshot)
  -> WindowSnapshot
{
  WindowSnapshot(
    runtimeClass: runtimeClass,
    title: "Test",
    identifier: nil,
    isKey: true,
    isMain: true,
    isVisible: true,
    isPanel: false,
    frame: Rect(x: 0, y: 0, width: 400, height: 300),
    contentView: contentView,
    childWindows: [])
}

/// The little known tree used across the suite: a content view (NSView) with two
/// NSTextField children and one NSButton — enough to pin same-class ordinals and
/// distinct mnemonics in one walk.
private func knownTree() -> WindowSnapshot {
  let content = view(
    "NSView",
    children: [
      view("NSTextField", text: "first"),
      view("NSTextField", text: "second"),
      view("NSButton", text: "OK"),
    ])
  return window(contentView: content)
}

// MARK: - Node-id suite

@Suite(.spec("domain.uitool.node-id"))
struct NodeIDFoundationTests {

  @Test
  func `a node id stringifies as epoch colon path with no pointer tag in the pure core`() {
    let id = NodeID(epoch: 7, structuralPath: "w0/cv/tv0")
    #expect(id.description == "7:w0/cv/tv0")
    #expect(id.pointerTag == nil)
  }

  @Test
  func `a supplied pointer tag adds the hash suffix`() {
    let id = NodeID(epoch: 7, structuralPath: "w0/cv", pointerTag: "a3f9")
    #expect(id.description == "7:w0/cv#a3f9")
  }

  @Test
  func `node ids are deterministic and legible breadcrumbs`() {
    let tree = NodeTree(windows: [knownTree()], epoch: 3)
    // Re-building the same forest mints byte-identical paths.
    let again = NodeTree(windows: [knownTree()], epoch: 3)
    let firstField = tree.lookup(NodeID(epoch: 3, structuralPath: "w0/cv/tf0"))
    let firstFieldAgain = again.lookup(NodeID(epoch: 3, structuralPath: "w0/cv/tf0"))
    #expect(firstField != nil)
    #expect(firstFieldAgain?.id.structuralPath == firstField?.id.structuralPath)
  }

  @Test
  func `same-class siblings get distinct ordinals and other classes get their own mnemonic`() {
    let tree = NodeTree(windows: [knownTree()], epoch: 1)
    // Two NSTextFields → tf0, tf1; the NSButton → b0. The breadcrumb is guessable.
    #expect(tree.lookup(NodeID(epoch: 1, structuralPath: "w0/cv/tf0"))?.snapshot.text == "first")
    #expect(tree.lookup(NodeID(epoch: 1, structuralPath: "w0/cv/tf1"))?.snapshot.text == "second")
    #expect(tree.lookup(NodeID(epoch: 1, structuralPath: "w0/cv/b0"))?.snapshot.text == "OK")
  }

  @Test
  func `the class mnemonic drops the framework prefix and lowercases the initials`() {
    #expect(StructuralPath.mnemonic(forClass: "NSTableView") == "tv")
    #expect(StructuralPath.mnemonic(forClass: "NSScrollView") == "sv")
    #expect(StructuralPath.mnemonic(forClass: "NSTextField") == "tf")
    #expect(StructuralPath.mnemonic(forClass: "NSButton") == "b")
  }

  @Test
  func `resolving a real id returns its node`() throws {
    let tree = NodeTree(windows: [knownTree()], epoch: 9)
    let resolved = try tree.resolve(NodeID(epoch: 9, structuralPath: "w0/cv/tf1"))
    #expect(resolved.snapshot.text == "second")
    #expect(resolved.parent?.structuralPath == "w0/cv")
  }

  @Test
  func `a path that does not resolve is STALE_NODE`() {
    let tree = NodeTree(windows: [knownTree()], epoch: 2)
    let phantom = NodeID(epoch: 2, structuralPath: "w0/cv/tf9")
    #expect(throws: UIToolError.staleNode(phantom)) {
      try tree.resolve(phantom)
    }
  }

  @Test
  func `a class-echo mismatch at a real path is STALE_NODE`() {
    // The forest at epoch 1 has tf0 = NSTextField. A re-walked forest where that
    // slot is now an NSButton (a recycled slot) must NOT resolve a held tf0 id.
    let mutated = window(
      contentView: view("NSView", children: [view("NSButton", text: "recycled")]))
    let tree = NodeTree(windows: [mutated], epoch: 1)
    let heldTextField = NodeID(epoch: 1, structuralPath: "w0/cv/tf0")
    // The mutated tree minted b0 for the button, so tf0 is absent → stale.
    #expect(throws: UIToolError.staleNode(heldTextField)) {
      try tree.resolve(heldTextField)
    }
  }

  @Test
  func `an id from a different epoch never resolves`() {
    let tree = NodeTree(windows: [knownTree()], epoch: 5)
    let stale = NodeID(epoch: 4, structuralPath: "w0/cv/tf0")
    #expect(tree.lookup(stale) == nil)
  }

  @Test
  func `a node id round-trips through its string form`() throws {
    let id = NodeID(epoch: 7, structuralPath: "w0/cv/tv0/tr3/c1")
    // The wire form is produced under the AgentCLI contract, which does not escape
    // slashes; a raw JSONEncoder would emit "w0\/cv\/…".
    let encoder = JSONEncoder()
    encoder.outputFormatting = .withoutEscapingSlashes
    let encoded = try encoder.encode(id)
    let decoded = try JSONDecoder().decode(NodeID.self, from: encoded)
    #expect(decoded == id)
    #expect(String(decoding: encoded, as: UTF8.self) == "\"7:w0/cv/tv0/tr3/c1\"")
  }
}

// MARK: - Node-projection suite

@Suite(.spec("domain.uitool.node"))
struct NodeFoundationTests {

  @Test
  func `a view projects to the default field set under its node id`() throws {
    let snapshot = view(
      "NSTextField",
      frame: Rect(x: 1, y: 2, width: 30, height: 40),
      text: "Inbox",
      font: FontSnapshot(
        family: "SF", size: 13, weightTrait: 0, weightName: "regular",
        postScriptName: ".SFNS-Regular", traits: []))
    let id = NodeID(epoch: 7, structuralPath: "w0/cv/tf0")
    let parent = NodeID(epoch: 7, structuralPath: "w0/cv")

    let node = Node.projecting(snapshot, id: id, parent: parent)

    #expect(node.node == "7:w0/cv/tf0")
    #expect(node.parent == "7:w0/cv")
    #expect(node.class == "NSTextField")
    #expect(node.text == "Inbox")
    #expect(node.font?.family == "SF")
    #expect(node.childCount == 0)
    #expect(node.constraintsCount == 0)
    // Include-only facets are nil by default.
    #expect(node.superclasses == nil)
    #expect(node.blendingMode == nil)
    #expect(node.layer == nil)
    #expect(node.constraints == nil)
  }

  @Test
  func `the projection rounds frame and alpha to one decimal place`() {
    let snapshot = view(
      "NSView",
      frame: Rect(x: 1.04, y: 2.06, width: 30.449, height: 40.95),
      alpha: 0.847)
    let node = Node.projecting(
      snapshot, id: NodeID(epoch: 1, structuralPath: "w0/cv"), parent: nil)

    #expect(node.frame.x == 1.0)
    #expect(node.frame.y == 2.1)
    #expect(node.frame.width == 30.4)
    #expect(node.frame.height == 41.0)
    #expect(node.alpha == 0.8)
  }

  @Test
  func `a content view root projects with no parent and nested children`() throws {
    let tree = NodeTree(windows: [knownTree()], epoch: 4)
    let resolved = try tree.resolve(NodeID(epoch: 4, structuralPath: "w0/cv"))
    let root = Node.projecting(
      resolved.snapshot, id: resolved.id, parent: resolved.parent, include: [], depth: .max)

    #expect(root.parent == nil)
    #expect(root.node == "4:w0/cv")
    #expect(root.class == "NSView")
    let children = try #require(root.children)
    #expect(children.count == 3)
    #expect(children.map(\.class) == ["NSTextField", "NSTextField", "NSButton"])
    #expect(children[0].node == "4:w0/cv/tf0")
    #expect(children[1].node == "4:w0/cv/tf1")
    #expect(children[2].node == "4:w0/cv/b0")
  }

  @Test
  func `include facets are populated only when requested`() throws {
    let snapshot = view(
      "NSVisualEffectView",
      material: "sidebar",
      blendingMode: "behindWindow",
      superclasses: ["NSView", "NSObject"])
    let id = NodeID(epoch: 1, structuralPath: "w0/cv/vev0")

    let plain = Node.projecting(snapshot, id: id, parent: nil)
    #expect(plain.material == "sidebar")  // material is a DEFAULT field
    #expect(plain.blendingMode == nil)  // blendingMode is include-only
    #expect(plain.superclasses == nil)

    let enriched = Node.projecting(
      snapshot, id: id, parent: nil, include: [.blendingMode, .superclasses])
    #expect(enriched.blendingMode == "behindWindow")
    #expect(enriched.superclasses == ["NSView", "NSObject"])
  }

  @Test
  func `the node carries constraintsCount but not the full list by default`() {
    let constraints = ConstraintNode(
      translatesAutoresizingMaskIntoConstraints: false,
      intrinsicContentSize: IntrinsicSize(width: -1, height: -1),
      contentHuggingHorizontal: 250,
      contentHuggingVertical: 250,
      compressionResistanceHorizontal: 750,
      compressionResistanceVertical: 750,
      constraints: [])
    let snapshot = view("NSView", constraints: constraints)
    let id = NodeID(epoch: 1, structuralPath: "w0/cv")

    let plain = Node.projecting(snapshot, id: id, parent: nil)
    #expect(plain.constraintsCount == 0)
    #expect(plain.constraints == nil)

    let enriched = Node.projecting(snapshot, id: id, parent: nil, include: [.constraints])
    #expect(enriched.constraints != nil)
  }

  @Test
  func `depth zero stops at the root and marks it truncated`() throws {
    let tree = NodeTree(windows: [knownTree()], epoch: 1)
    let resolved = try tree.resolve(NodeID(epoch: 1, structuralPath: "w0/cv"))
    let root = Node.projecting(
      resolved.snapshot, id: resolved.id, parent: resolved.parent, include: [], depth: 0)
    #expect(root.children == nil)
    #expect(root.truncated)
    #expect(root.childCount == 3)  // the true subview count survives truncation
  }

  @Test
  func `a node is Codable and round-trips through JSON`() throws {
    let tree = NodeTree(windows: [knownTree()], epoch: 8)
    let resolved = try tree.resolve(NodeID(epoch: 8, structuralPath: "w0/cv"))
    let root = Node.projecting(
      resolved.snapshot, id: resolved.id, parent: resolved.parent, include: [], depth: .max)

    let encoded = try JSONEncoder().encode(root)
    let decoded = try JSONDecoder().decode(Node.self, from: encoded)
    #expect(decoded.node == root.node)
    #expect(decoded.class == root.class)
    #expect(decoded.children?.count == root.children?.count)
    #expect(decoded.children?.first?.text == "first")
  }
}

// MARK: - Error-mapping suite

@Suite(.spec("domain.uitool.ipc"))
struct UIToolErrorTests {

  @Test
  func `the exit-code map matches the ipc spec`() {
    #expect(UIToolError.badSelector("x").exitCode == 2)
    #expect(UIToolError.unknownField("x").exitCode == 2)
    #expect(UIToolError.badPredicate("x").exitCode == 2)
    #expect(UIToolError.notAttached.exitCode == 4)
    #expect(UIToolError.staleNode(NodeID(epoch: 1, structuralPath: "w0")).exitCode == 5)
    #expect(UIToolError.timeout.exitCode == 7)
    // NO_WINDOWS is an empty result, not a failure exit.
    #expect(UIToolError.noWindows.exitCode == 0)
  }

  @Test
  func `the wire codes are the closed vocabulary`() {
    #expect(UIToolError.badSelector("x").code == "BAD_SELECTOR")
    #expect(UIToolError.unknownField("x").code == "UNKNOWN_FIELD")
    #expect(UIToolError.badPredicate("x").code == "BAD_PREDICATE")
    #expect(UIToolError.staleNode(NodeID(epoch: 1, structuralPath: "w0")).code == "STALE_NODE")
    #expect(UIToolError.notAttached.code == "NOT_ATTACHED")
    #expect(UIToolError.noWindows.code == "NO_WINDOWS")
    #expect(UIToolError.timeout.code == "TIMEOUT")
  }
}
