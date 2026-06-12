import Foundation
import RuntimeKit
import TestSupport
import Testing

@testable import UIToolCore

// SPEC: command.uitool.find
//
// The read-verb oracle: synthetic ViewSnapshot/WindowSnapshot VALUES built directly
// via their public inits (no AppKit, no window server, no injection), assembled into
// a NodeTree, and run through the four pure verbs — windows, tree, find, node. This
// is the purity boundary: the verbs are pure over snapshot values; nothing here
// touches a live view or AppKitWalker. The known tree (a window whose content view
// holds a labelled NSButton, two NSTextFields one of which is titled "Inbox", and a
// nested NSScrollView → NSTableView → rows) exercises window enumeration, depth-
// bounded truncation, selector + --where matching, --limit / --count-only, node
// resolution + staleness, --fields projection + the unknown-field error, and the
// --include constraints inline.

// MARK: - Synthetic snapshot builders (no AppKit)

/// A leaf `ViewSnapshot` with sensible defaults; only the facets a test cares about
/// are overridden, so a construction reads as "an NSButton at this frame".
private func view(
  _ runtimeClass: String,
  frame: Rect = Rect(x: 0, y: 0, width: 10, height: 10),
  hidden: Bool = false,
  alpha: Double = 1,
  identifier: String? = nil,
  text: String? = nil,
  axRole: String? = nil,
  material: String? = nil,
  blendingMode: String? = nil,
  layer: LayerSnapshot? = nil,
  constraints: ConstraintNode? = nil,
  superclasses: [String] = ["NSView", "NSResponder", "NSObject"],
  swiftUIBoundary: Bool = false,
  children: [ViewSnapshot] = []
) -> ViewSnapshot {
  ViewSnapshot(
    runtimeClass: runtimeClass,
    superclasses: superclasses,
    frame: frame,
    frameTopLeft: frame,
    isFlipped: false,
    hidden: hidden,
    alpha: alpha,
    identifier: identifier,
    text: text,
    axRole: axRole,
    font: nil,
    material: material,
    blendingMode: blendingMode,
    layer: layer,
    constraints: constraints,
    swiftUIBoundary: swiftUIBoundary,
    childCount: children.count,
    truncated: false,
    children: children)
}

/// A window wrapping a content view — a forest root the walk seeds from.
private func window(
  _ runtimeClass: String = "NSWindow", title: String? = "Test", contentView: ViewSnapshot
) -> WindowSnapshot {
  WindowSnapshot(
    runtimeClass: runtimeClass,
    title: title,
    identifier: nil,
    isKey: true,
    isMain: true,
    isVisible: true,
    isPanel: false,
    frame: Rect(x: 0, y: 0, width: 400, height: 300),
    contentView: contentView,
    childWindows: [])
}

/// The control-bearing constraint a node carries so `--include constraints` has
/// something to inline. Built directly via the RuntimeKit memberwise inits — the
/// same construction the node-foundation suite uses.
private func widthConstraint() -> ConstraintNode {
  ConstraintNode(
    translatesAutoresizingMaskIntoConstraints: false,
    intrinsicContentSize: IntrinsicSize(width: -1, height: -1),
    contentHuggingHorizontal: 250,
    contentHuggingVertical: 250,
    compressionResistanceHorizontal: 750,
    compressionResistanceVertical: 750,
    constraints: [])
}

/// The known tree across the suite. A window whose content view holds:
///   - an `NSButton` (through `NSControl`) titled "OK"
///   - an `NSTextField` titled "Inbox Unread" carrying a constraint
///   - an `NSScrollView` → `NSTableView` → three `NSTableRowView` rows (the deep
///     branch the depth bound truncates)
/// Enough to pin window enumeration, depth truncation, hierarchy `~`, substring,
/// limit/count, and the constraint inline in one walk.
private func knownTree(epoch: Int = 7) -> NodeTree {
  let button = view(
    "NSButton", text: "OK",
    superclasses: ["NSControl", "NSView", "NSResponder", "NSObject"])
  let inbox = view(
    "NSTextField", text: "Inbox Unread", constraints: widthConstraint(),
    superclasses: ["NSControl", "NSView", "NSResponder", "NSObject"])
  let rows = (0..<3).map { view("NSTableRowView", text: "row\($0)") }
  let table = view("NSTableView", children: rows)
  let scroll = view("NSScrollView", children: [table])
  let content = view("NSView", children: [button, inbox, scroll])
  return NodeTree(windows: [window(contentView: content)], epoch: epoch)
}

/// Decode one JSON-Lines record into a key/value map for field-presence assertions.
private func record(_ line: String) throws -> [String: Any] {
  let object = try JSONSerialization.jsonObject(with: Data(line.utf8))
  return try #require(object as? [String: Any])
}

// MARK: - windows

@Suite(.spec("command.uitool.windows"))
struct WindowsVerbTests {

  @Test(.scenario("scenario.uitool.windows-enumerate.happy-path"))
  func `windows lists one window record per top-level window`() throws {
    let twoWindows = NodeTree(
      windows: [
        window(contentView: view("NSView", children: [view("NSButton")])),
        window(contentView: view("NSView")),
      ], epoch: 7)
    let result = try Verbs.windows(twoWindows)

    #expect(result.returned == 2)
    #expect(result.totalMatched == 2)
    #expect(!result.truncated)
    let first = try record(result.lines[0])
    #expect(first["node"] as? String == "7:w0")  // the bare window root, not its w0/cv content view
    #expect(first["parent"] as? String == nil)
    #expect(first["class"] as? String == "NSWindow")
    #expect(first["title"] as? String == "Test")
    #expect(first["key"] as? Bool == true)
    #expect(first["main"] as? Bool == true)
  }

  @Test(.scenario("scenario.uitool.windows-enumerate.empty"))
  func `an app with no windows yields an empty list with totalMatched zero`() throws {
    let empty = NodeTree(windows: [], epoch: 7)
    let result = try Verbs.windows(empty)
    #expect(result.lines.isEmpty)
    #expect(result.totalMatched == 0)
  }

  @Test(.scenario("scenario.uitool.windows-enumerate.deterministic"))
  func `a repeat listing of an unchanged app is byte-identical`() throws {
    let first = try Verbs.windows(knownTree()).lines
    let again = try Verbs.windows(knownTree()).lines
    #expect(first == again)
  }

  @Test
  func `a window record carries window-only fields and no view-node fields`() throws {
    let result = try Verbs.windows(knownTree())
    #expect(result.returned == 1)
    let root = try record(result.lines[0])
    // Window-only facts are present...
    #expect(root["title"] as? String == "Test")
    #expect(root["key"] as? Bool == true)
    #expect(root["frame"] != nil)
    // ...and none of the view-relative fields a window root has no enclosing view for.
    #expect(root["children"] == nil)
    #expect(root["childCount"] == nil)
    #expect(root["frameTopLeft"] == nil)
    #expect(root["isFlipped"] == nil)
  }
}

// MARK: - tree

@Suite(.spec("command.uitool.tree"))
struct TreeVerbTests {

  private func contentRoot(_ tree: NodeTree) -> NodeID {
    NodeID(epoch: 7, structuralPath: "w0/cv")
  }

  @Test(.scenario("scenario.uitool.tree-walk.bounded"))
  func `a depth-bounded walk goes no deeper than the requested depth`() throws {
    let tree = knownTree()
    let result = try Verbs.tree(at: contentRoot(tree), in: tree, maxDepth: 1)
    let paths = try result.lines.map { try record($0)["node"] as? String }

    // depth 1: the content view + its three direct children; the table's rows
    // (two levels down) are never reached.
    #expect(paths.contains("7:w0/cv"))
    #expect(paths.contains("7:w0/cv/b0"))
    #expect(paths.contains("7:w0/cv/tf0"))
    #expect(paths.contains("7:w0/cv/sv0"))
    #expect(!paths.contains { $0?.contains("/tv0/") == true })
  }

  @Test(.scenario("scenario.uitool.tree-walk.truncated"))
  func `a branch cut off at the depth limit is marked truncated with its child count`() throws {
    let tree = knownTree()
    let result = try Verbs.tree(at: contentRoot(tree), in: tree, maxDepth: 1)
    // The NSScrollView sits at the depth floor and still has a child → truncated.
    let scroll = try result.lines.map { try record($0) }.first {
      $0["node"] as? String == "7:w0/cv/sv0"
    }
    let scrollRecord = try #require(scroll)
    #expect(scrollRecord["truncated"] as? Bool == true)
    #expect(scrollRecord["childCount"] as? Int == 1)
    #expect(scrollRecord["children"] == nil)
  }

  @Test(.scenario("scenario.uitool.tree-walk.complete"))
  func `a fully-contained subtree is never marked truncated`() throws {
    let tree = knownTree()
    // The button leaf is fully contained at any depth: childCount 0, not truncated.
    let result = try Verbs.tree(at: contentRoot(tree), in: tree, maxDepth: 5)
    let button = try result.lines.map { try record($0) }.first {
      $0["node"] as? String == "7:w0/cv/b0"
    }
    let buttonRecord = try #require(button)
    #expect(buttonRecord["truncated"] as? Bool == false)
    #expect(buttonRecord["childCount"] as? Int == 0)
  }

  @Test(.scenario("scenario.uitool.tree-walk.subtree-root"))
  func `a walk from a chosen subtree root excludes ancestors and siblings`() throws {
    let tree = knownTree()
    let scrollRoot = NodeID(epoch: 7, structuralPath: "w0/cv/sv0")
    let result = try Verbs.tree(at: scrollRoot, in: tree, maxDepth: 5)
    let paths = try result.lines.compactMap { try record($0)["node"] as? String }

    #expect(paths.first == "7:w0/cv/sv0")  // the requested node is first
    #expect(!paths.contains("7:w0/cv"))  // no ancestor
    #expect(!paths.contains("7:w0/cv/b0"))  // no sibling
    // NSTableRowView → mnemonic "trv" (stripped-prefix CamelCase initials).
    #expect(paths.contains("7:w0/cv/sv0/tv0/trv0"))  // its own descendants are present
  }

  @Test(.scenario("scenario.uitool.tree-walk.stale"))
  func `a walk from a stale root id is STALE_NODE`() {
    let tree = knownTree()
    let phantom = NodeID(epoch: 7, structuralPath: "w0/cv/tf9")
    #expect(throws: UIToolError.staleNode(phantom)) {
      _ = try Verbs.tree(at: phantom, in: tree, maxDepth: 2)
    }
  }

  @Test(.scenario("scenario.uitool.tree-project.narrow"))
  func `a narrow field projection emits only the chosen fields per node`() throws {
    let tree = knownTree()
    let result = try Verbs.tree(
      at: contentRoot(tree), in: tree, maxDepth: 1, fields: ["node", "class"])
    let first = try record(result.lines[0])
    #expect(Set(first.keys) == ["node", "class"])
  }

  @Test(.scenario("scenario.uitool.tree-project.unknown-field"))
  func `an unknown field path is rejected and no hierarchy is returned`() {
    let tree = knownTree()
    #expect(throws: UIToolError.unknownField("bogus")) {
      _ = try Verbs.tree(at: contentRoot(tree), in: tree, maxDepth: 2, fields: ["node", "bogus"])
    }
  }

  @Test
  func `a where filter selects emitted nodes without pruning the walk`() throws {
    let tree = knownTree()
    let predicate = try Predicate(parsing: "class ~ 'NSTableRowView'")
    // Rows are two levels below the scroll view; a shallow non-match (the scroll
    // view) must not hide the deep matches.
    let result = try Verbs.tree(
      at: contentRoot(tree), in: tree, maxDepth: 5, where: predicate)
    #expect(result.totalMatched == 3)
    #expect(result.returned == 3)
  }

  @Test
  func `count-only sizes the walk without transferring node bodies`() throws {
    let tree = knownTree()
    let result = try Verbs.tree(
      at: contentRoot(tree), in: tree, maxDepth: 5, countOnly: true)
    #expect(result.lines.isEmpty)
    #expect(result.returned == 0)
    #expect(result.totalMatched > 0)  // the whole subtree matched, just not emitted
  }
}

// MARK: - find

@Suite(.spec("command.uitool.find"))
struct FindVerbTests {

  @Test(.scenario("scenario.uitool.find-locate.projection"))
  func `find returns the matching node with a stable handle and narrow fields`() throws {
    let tree = knownTree()
    let predicate = try Predicate(parsing: "class ~ 'NSTextField' and text *= 'Inbox'")
    let result = try Verbs.find(in: tree, where: predicate, fields: ["node", "class"])

    #expect(result.returned == 1)
    #expect(result.totalMatched == 1)
    let only = try record(result.lines[0])
    #expect(only["node"] as? String == "7:w0/cv/tf0")  // a stable handle to drill into
    #expect(Set(only.keys) == ["node", "class"])
  }

  @Test
  func `a narrowed find retains the node handle even when --fields omits it`() throws {
    let tree = knownTree()
    let result = try Verbs.find(
      in: tree, selector: try Selector(parsing: "NSTextField"), fields: ["class"])
    #expect(result.returned == 1)
    let only = try record(result.lines[0])
    // --fields named only `class`, but the id is the handle — it survives so the
    // match stays addressable for a follow-up `node`/`tree` call.
    #expect(only["node"] as? String == "7:w0/cv/tf0")
    #expect(Set(only.keys) == ["node", "class"])
  }

  @Test
  func `a find with neither a selector nor a predicate is a usage error`() {
    // A bare find would slurp every node — the unbounded read the surface forbids.
    #expect(throws: UIToolError.badSelector("find requires a selector or a --where predicate")) {
      _ = try Verbs.find(in: knownTree())
    }
  }

  @Test(.scenario("scenario.uitool.find-locate.limit"))
  func `a limit caps the returned records but not the total matched count`() throws {
    let tree = knownTree()
    let selector = try Selector(parsing: "NSTableRowView")
    let result = try Verbs.find(in: tree, selector: selector, limit: 2)

    #expect(result.returned == 2)  // capped
    #expect(result.totalMatched == 3)  // the full match count survives the cap
    #expect(result.truncated)  // the single canonical "more exist" flag
  }

  @Test(.scenario("scenario.uitool.find-locate.empty"))
  func `a selector matching nothing yields an empty result, not an error`() throws {
    let tree = knownTree()
    let selector = try Selector(parsing: "NSComboBox")
    let result = try Verbs.find(in: tree, selector: selector)
    #expect(result.lines.isEmpty)
    #expect(result.totalMatched == 0)
    #expect(!result.truncated)
  }

  @Test(.scenario("scenario.uitool.find-count.matches"))
  func `count-only reports the match count and returns no node bodies`() throws {
    let tree = knownTree()
    let selector = try Selector(parsing: "NSTableRowView")
    let result = try Verbs.find(in: tree, selector: selector, countOnly: true)
    #expect(result.totalMatched == 3)
    #expect(result.lines.isEmpty)
    #expect(result.returned == 0)
  }

  @Test(.scenario("scenario.uitool.find-count.broad"))
  func `count-only reports the full total regardless of the result cap`() throws {
    let tree = knownTree()
    let selector = try Selector(parsing: "NSTableRowView")
    // A tiny limit must not affect the reported count under --count-only.
    let result = try Verbs.find(in: tree, selector: selector, limit: 1, countOnly: true)
    #expect(result.totalMatched == 3)
    #expect(result.returned == 0)
  }

  @Test
  func `a class selector resolves through the runtime hierarchy`() throws {
    let tree = knownTree()
    // NSButton's chain includes NSControl, so an NSControl selector finds it.
    let result = try Verbs.find(in: tree, selector: try Selector(parsing: "NSControl"))
    let classes = try result.lines.compactMap { try record($0)["class"] as? String }
    #expect(classes.contains("NSButton"))
    #expect(classes.contains("NSTextField"))
    #expect(!classes.contains("NSScrollView"))  // not an NSControl
  }
}

// MARK: - node

@Suite(.spec("command.uitool.node"))
struct NodeVerbTests {

  @Test(.scenario("scenario.uitool.node-read.default"))
  func `node reads one node with the default projection and no pull-on-demand facets`() throws {
    let tree = knownTree()
    let json = try Verbs.node(at: NodeID(epoch: 7, structuralPath: "w0/cv/tf0"), in: tree)
    let object = try record(json)

    #expect(object["node"] as? String == "7:w0/cv/tf0")
    #expect(object["class"] as? String == "NSTextField")
    #expect(object["constraintsCount"] as? Int == 0)  // default carries the count only
    #expect(object["constraints"] == nil)  // not the full list
    #expect(object["superclasses"] == nil)
    #expect(object["layer"] == nil)
  }

  @Test(.scenario("scenario.uitool.node-read.included"))
  func `node with include constraints inlines the full constraint list`() throws {
    let tree = knownTree()
    let json = try Verbs.node(
      at: NodeID(epoch: 7, structuralPath: "w0/cv/tf0"), in: tree, include: [.constraints])
    let object = try record(json)

    #expect(object["constraints"] != nil)  // the full ConstraintNode is inlined
    #expect(object["constraintsCount"] != nil)  // alongside the still-present count
    #expect(object["layer"] == nil)  // an unrequested facet stays absent
  }

  @Test(.scenario("scenario.uitool.node-read.facet-absent"))
  func `a requested facet that does not apply is emitted as null, not omitted`() throws {
    let tree = knownTree()  // the text field has no backing layer
    let json = try Verbs.node(
      at: NodeID(epoch: 7, structuralPath: "w0/cv/tf0"), in: tree, include: [.layer])
    // The layer facet was requested but the node is unbacked → null, not absent, so
    // the agent distinguishes "asked, absent" from "not asked".
    #expect(json.contains("\"layer\""))
    #expect(json.contains("\"layer\" : null") || json.contains("\"layer\": null"))
  }

  @Test(.scenario("scenario.uitool.node-read.single"))
  func `node reads exactly one node, never its subtree`() throws {
    let tree = knownTree()
    // The scroll view has a child; node must still return one object, no children.
    let json = try Verbs.node(at: NodeID(epoch: 7, structuralPath: "w0/cv/sv0"), in: tree)
    let object = try record(json)
    #expect(object["children"] == nil)
    #expect(object["childCount"] as? Int == 1)
  }

  @Test(.scenario("scenario.uitool.node-stale-detection.recycled"))
  func `a node id whose path resolves to a different class is STALE_NODE`() {
    // The held id is a text field; the live tree at that path is now a button.
    let mutated = NodeTree(
      windows: [window(contentView: view("NSView", children: [view("NSButton")]))], epoch: 7)
    let heldTextField = NodeID(epoch: 7, structuralPath: "w0/cv/tf0")
    #expect(throws: UIToolError.staleNode(heldTextField)) {
      _ = try Verbs.node(at: heldTextField, in: mutated)
    }
  }

  @Test(.scenario("scenario.uitool.node-stale-detection.epoch"))
  func `a node id minted in an earlier epoch is STALE_NODE`() {
    let tree = knownTree(epoch: 8)  // re-attached: epoch bumped to 8
    let heldFromEarlier = NodeID(epoch: 7, structuralPath: "w0/cv/tf0")
    #expect(throws: UIToolError.staleNode(heldFromEarlier)) {
      _ = try Verbs.node(at: heldFromEarlier, in: tree)
    }
  }

  @Test
  func `include frame is a no-op that changes nothing`() throws {
    let tree = knownTree()
    let id = NodeID(epoch: 7, structuralPath: "w0/cv/tf0")
    // --include frame maps to no facet; the record equals the default projection.
    let plain = try Verbs.node(at: id, in: tree)
    let withFrame = try Verbs.node(
      at: id, in: tree, include: Projection.includeFacets(["frame"]))
    #expect(plain == withFrame)
  }

  @Test
  func `a deferred ivars facet is rejected as not available in this build`() {
    #expect(throws: UIToolError.self) {
      _ = try Projection.includeFacets(["ivars"])
    }
  }
}

// MARK: - determinism

@Suite(.spec("command.uitool.find"))
struct VerbDeterminismTests {

  @Test
  func `find output is byte-stable across runs with sorted keys`() throws {
    let first = try Verbs.find(in: knownTree(), selector: try Selector(parsing: "NSTableRowView"))
    let again = try Verbs.find(in: knownTree(), selector: try Selector(parsing: "NSTableRowView"))
    #expect(first.lines == again.lines)
    // Sorted keys: assert the encoder sorted by checking two always-present default
    // fields whose keys have a known lexicographic order — childCount < class.
    let line = first.lines[0]
    let childCountIndex = try #require(line.range(of: "childCount"))
    let classIndex = try #require(line.range(of: "\"class\""))
    #expect(childCountIndex.lowerBound < classIndex.lowerBound)
  }

  @Test
  func `frame fields are projected at one decimal place`() throws {
    let tree = NodeTree(
      windows: [
        window(
          contentView: view(
            "NSView", frame: Rect(x: 1.04, y: 2.06, width: 30.449, height: 40.95)))
      ], epoch: 7)
    let json = try Verbs.node(at: NodeID(epoch: 7, structuralPath: "w0/cv"), in: tree)
    // 1-dp rounding: 30.449 → 30.4, 40.95 → 41 — byte-stable in the JSON.
    #expect(json.contains("30.4"))
    #expect(!json.contains("30.449"))
  }
}
