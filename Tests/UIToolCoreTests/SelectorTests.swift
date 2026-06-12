import Foundation
import RuntimeKit
import TestSupport
import Testing

@testable import UIToolCore

// SPEC: domain.uitool.selector
//
// The selector + predicate oracle: synthetic ViewSnapshot/WindowSnapshot VALUES
// built directly via their public inits (no AppKit, no window server, no
// injection), assembled into a NodeTree, and matched against parsed selectors and
// --where predicates. This is the purity boundary — the grammar is pure over
// snapshot values; nothing here touches a live view or AppKitWalker. The known
// tree (a window whose content view holds an NSButton, an NSTextField titled
// "Inbox Unread", and a wide NSView) exercises hierarchy ~, substring, geometry,
// the child-vs-descendant distinction, case-insensitive regex, and every usage
// error (bad regex → badSelector, malformed --where → badPredicate, unknown
// attribute → unknownField).

// MARK: - Synthetic snapshot builders (no AppKit)

/// A leaf `ViewSnapshot` with sensible defaults; only the facets a test cares
/// about are overridden, so a construction reads as "an NSButton at this frame".
/// `superclasses` carries the runtime chain `~` resolves against.
private func view(
  _ runtimeClass: String,
  frame: Rect = Rect(x: 0, y: 0, width: 10, height: 10),
  hidden: Bool = false,
  alpha: Double = 1,
  identifier: String? = nil,
  text: String? = nil,
  axRole: String? = nil,
  material: String? = nil,
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
    blendingMode: nil,
    layer: nil,
    constraints: nil,
    swiftUIBoundary: swiftUIBoundary,
    childCount: children.count,
    truncated: false,
    children: children)
}

/// A window wrapping a content view — the forest root the walk seeds from.
private func window(contentView: ViewSnapshot) -> WindowSnapshot {
  WindowSnapshot(
    runtimeClass: "NSWindow",
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

/// The known tree: a content view holding
///   - an `NSButton` (superclass chain through `NSControl`) — the `~` hierarchy case
///   - an `NSTextField` titled "Inbox Unread" — the substring case
///   - a wide `NSView` (frame width 240) — the geometry case
/// and, nested under a stack view, a direct-child `NSTextField` — the
/// child-vs-descendant case.
private func knownTree() -> NodeTree {
  let button = view(
    "NSButton",
    text: "OK",
    superclasses: ["NSControl", "NSView", "NSResponder", "NSObject"])
  let inboxField = view(
    "NSTextField",
    text: "Inbox Unread",
    superclasses: ["NSControl", "NSView", "NSResponder", "NSObject"])
  let wideView = view(
    "NSView", frame: Rect(x: 0, y: 0, width: 240, height: 20),
    superclasses: ["NSResponder", "NSObject"])
  let stackChildField = view(
    "NSTextField",
    text: "in stack",
    superclasses: ["NSControl", "NSView", "NSResponder", "NSObject"])
  let stack = view("NSStackView", children: [stackChildField])

  let content = view("NSView", children: [button, inboxField, wideView, stack])
  return NodeTree(windows: [window(contentView: content)], epoch: 1)
}

/// Resolve a structural-path leaf to its projected default node, for matching.
private func node(_ path: String, in tree: NodeTree) throws -> Node {
  let resolved = try #require(tree.lookup(NodeID(epoch: 1, structuralPath: path)))
  return Node.projecting(resolved.snapshot, id: resolved.id, parent: resolved.parent, depth: 0)
}

// MARK: - Structural selector suite

@Suite(.spec("domain.uitool.selector"))
struct SelectorTests {

  @Test
  func `an NSControl selector matches an NSButton through the runtime hierarchy`() throws {
    let tree = knownTree()
    let button = try node("w0/cv/b0", in: tree)
    let selector = try Selector(parsing: "NSControl")
    // NSButton's superclasses include NSControl, so the class-of (~) match holds.
    #expect(selector.matches(button, in: tree))
    // A plain NSView is NOT an NSControl — the hierarchy match is exact per rung.
    let wide = try node("w0/cv/v0", in: tree)
    #expect(!selector.matches(wide, in: tree))
  }

  @Test
  func `an exact class selector still matches its own class`() throws {
    let tree = knownTree()
    let button = try node("w0/cv/b0", in: tree)
    #expect(try Selector(parsing: "NSButton").matches(button, in: tree))
  }

  @Test
  func `a wildcard matches any class`() throws {
    let tree = knownTree()
    let button = try node("w0/cv/b0", in: tree)
    #expect(try Selector(parsing: "*").matches(button, in: tree))
  }

  @Test
  func `an attribute substring selector matches a title containing the needle`() throws {
    let tree = knownTree()
    let inbox = try node("w0/cv/tf0", in: tree)
    // NSView[title*="Inbox"] — title surfaces the node's text handle; substring.
    #expect(try Selector(parsing: #"NSView[title*="Inbox"]"#).matches(inbox, in: tree))
    let button = try node("w0/cv/b0", in: tree)
    #expect(!(try Selector(parsing: #"NSView[title*="Inbox"]"#).matches(button, in: tree)))
  }

  @Test
  func `substring matching is case-insensitive`() throws {
    let tree = knownTree()
    let inbox = try node("w0/cv/tf0", in: tree)
    #expect(try Selector(parsing: #"*[text*="inbox"]"#).matches(inbox, in: tree))
  }

  @Test
  func `a geometry attribute selector compares the frame width`() throws {
    let tree = knownTree()
    let wide = try node("w0/cv/v0", in: tree)  // width 240
    let narrow = try node("w0/cv/b0", in: tree)  // width 10
    #expect(try Selector(parsing: "NSView[frame-w>200]").matches(wide, in: tree))
    #expect(!(try Selector(parsing: "NSView[frame-w>200]").matches(narrow, in: tree)))
  }

  @Test
  func `a direct-child selector distinguishes from a descendant selector`() throws {
    let tree = knownTree()
    let stackField = try node("w0/cv/sv0/tf0", in: tree)  // parent is the NSStackView
    let topInbox = try node("w0/cv/tf0", in: tree)  // parent is the content NSView

    // `>` is the IMMEDIATE parent. The stack field's parent is the NSStackView, so
    // `NSStackView > NSTextField` matches it but `NSStackView NSTextField` (an
    // ancestor anywhere) also matches it.
    #expect(try Selector(parsing: "NSStackView > NSTextField").matches(stackField, in: tree))
    #expect(try Selector(parsing: "NSStackView NSTextField").matches(stackField, in: tree))

    // The top inbox field's parent is the content NSView, NOT a stack view: neither
    // the direct-child nor the descendant stack-view selector matches it — this is
    // the distinction `>` vs descendant draws.
    #expect(!(try Selector(parsing: "NSStackView > NSTextField").matches(topInbox, in: tree)))
    #expect(!(try Selector(parsing: "NSStackView NSTextField").matches(topInbox, in: tree)))
  }

  @Test
  func `an invalid regex in a matches selector throws badSelector`() {
    // An unbalanced group never compiles — rejected at parse, before any node.
    #expect(throws: UIToolError.badSelector(#"(unterminated"#)) {
      _ = try Selector(parsing: #"NSView[text matches "(unterminated"]"#)
    }
  }

  @Test
  func `an unknown attribute in a selector throws unknownField`() {
    #expect(throws: UIToolError.unknownField("bogus")) {
      _ = try Selector(parsing: "NSView[bogus=1]")
    }
  }

  @Test
  func `a non-numeric geometry operand is a bad selector not a bad predicate`() {
    #expect(throws: UIToolError.self) {
      _ = try Selector(parsing: "NSView[frame-w>big]")
    }
    // And specifically badSelector, since this is selector context.
    do {
      _ = try Selector(parsing: "NSView[frame-w>big]")
      Issue.record("expected a throw")
    } catch UIToolError.badSelector {
      // correct
    } catch {
      Issue.record("expected badSelector, got \(error)")
    }
  }

  @Test
  func `an empty selector is malformed`() {
    #expect(throws: UIToolError.self) { _ = try Selector(parsing: "   ") }
    #expect(throws: UIToolError.self) { _ = try Selector(parsing: "NSView > ") }
  }

  @Test
  func `trailing input a combinator cannot consume is a bad selector`() {
    // The whole input must be consumed. The unsupported class glob `NS*View` parses
    // `NS`, then `*View` is left over — rejected rather than silently matching the
    // class literally named `NS`.
    #expect(throws: UIToolError.badSelector("unexpected trailing input in selector")) {
      _ = try Selector(parsing: "NS*View")
    }
    // A trailing `*` after a complete class selector is likewise unconsumable.
    #expect(throws: UIToolError.badSelector("unexpected trailing input in selector")) {
      _ = try Selector(parsing: "NSButton*")
    }
  }
}

// MARK: - Predicate (--where) suite

@Suite(.spec("domain.uitool.selector"))
struct PredicateTests {

  @Test
  func `a class-of predicate resolves the runtime hierarchy`() throws {
    let tree = knownTree()
    let button = try node("w0/cv/b0", in: tree)
    let predicate = try Predicate(parsing: "class ~ 'NSControl'")
    #expect(predicate.evaluate(button, in: tree))
    let wide = try node("w0/cv/v0", in: tree)
    #expect(!predicate.evaluate(wide, in: tree))
  }

  @Test
  func `a class-of predicate with no tree only sees the node's own class`() throws {
    let tree = knownTree()
    let button = try node("w0/cv/b0", in: tree)
    // No-tree evaluate can't walk the hierarchy: NSControl is a superclass, not the
    // node's own class, so it does not match without a tree.
    #expect(!(try Predicate(parsing: "class ~ 'NSControl'").evaluate(button)))
    #expect(try Predicate(parsing: "class ~ 'NSButton'").evaluate(button))
  }

  @Test
  func `and combines two comparisons`() throws {
    let tree = knownTree()
    let inbox = try node("w0/cv/tf0", in: tree)
    let predicate = try Predicate(parsing: "class ~ 'NSTextField' and text *= 'Inbox'")
    #expect(predicate.evaluate(inbox, in: tree))
    let button = try node("w0/cv/b0", in: tree)
    #expect(!predicate.evaluate(button, in: tree))
  }

  @Test
  func `or and not compose`() throws {
    let tree = knownTree()
    let button = try node("w0/cv/b0", in: tree)
    #expect(try Predicate(parsing: "text = 'OK' or hidden = true").evaluate(button))
    #expect(try Predicate(parsing: "not hidden = true").evaluate(button))
    #expect(!(try Predicate(parsing: "not text = 'OK'").evaluate(button)))
  }

  @Test
  func `geometry comparisons work in a predicate`() throws {
    let tree = knownTree()
    let wide = try node("w0/cv/v0", in: tree)
    #expect(try Predicate(parsing: "frame-w > 200 and hidden = false").evaluate(wide))
    let button = try node("w0/cv/b0", in: tree)
    #expect(!(try Predicate(parsing: "frame-w > 200").evaluate(button)))
  }

  @Test
  func `a matches regex predicate is case-insensitive and unanchored`() throws {
    let tree = knownTree()
    let inbox = try node("w0/cv/tf0", in: tree)
    // 'in.ox' matches "Inbox Unread" case-insensitively, unanchored.
    #expect(try Predicate(parsing: "text matches 'in.ox'").evaluate(inbox))
    // An explicit anchor narrows it: ^Inbox$ does NOT match "Inbox Unread".
    #expect(!(try Predicate(parsing: "text matches '^Inbox$'").evaluate(inbox)))
  }

  @Test
  func `parentheses override precedence`() throws {
    let tree = knownTree()
    let button = try node("w0/cv/b0", in: tree)  // text OK, not hidden
    // not (text = 'OK' or hidden = true) → not(true) → false.
    #expect(!(try Predicate(parsing: "not (text = 'OK' or hidden = true)").evaluate(button)))
  }

  @Test
  func `a malformed where throws badPredicate`() {
    #expect(throws: UIToolError.self) { _ = try Predicate(parsing: "frame-w >") }
    #expect(throws: UIToolError.self) { _ = try Predicate(parsing: "and hidden = true") }
    // Specifically badPredicate.
    do {
      _ = try Predicate(parsing: "hidden = true extra")
      Issue.record("expected a throw")
    } catch UIToolError.badPredicate {
      // correct
    } catch {
      Issue.record("expected badPredicate, got \(error)")
    }
  }

  @Test
  func `an unknown attribute in a where throws unknownField`() {
    #expect(throws: UIToolError.unknownField("bogus")) {
      _ = try Predicate(parsing: "bogus = 1")
    }
  }

  @Test
  func `an invalid regex in a where matches throws badSelector`() {
    // A bad regex is a selector-grade usage error even inside --where, per the spec.
    #expect(throws: UIToolError.badSelector(#"(unterminated"#)) {
      _ = try Predicate(parsing: #"text matches '(unterminated'"#)
    }
  }
}
