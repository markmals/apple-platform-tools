import AppKit
import Foundation
import ObjectiveC
import TestSupport
import Testing

@testable import RuntimeKit

// SPEC: domain.runtime.walker
//
// The constraint-snapshot oracle: a known view tree built in the test process on
// the main thread (no injection). A view with an activated `widthAnchor`
// equal-to-constant constraint pins the decomposition of one real
// `NSLayoutConstraint`; parent/child trees pin the touch filter, the ancestor
// walk, dedup, and the absent-second-item (constant) case. These tests touch
// AppKit, so they are `@MainActor` and need a logged-in (window-server) session.

// SPEC: domain.runtime.walker
@Suite(.spec("domain.runtime.walker"))
@MainActor
struct ConstraintNodeTests {

  @Test(.scenario("scenario.runtime.walker.width-constraint"))
  func `a width constraint decomposes to width = equal, constant 100, on the target`() throws {
    let view = NSView(frame: .zero)
    let width = view.widthAnchor.constraint(equalToConstant: 100)
    width.isActive = true

    let node = ConstraintNode.snapshot(of: view)
    let constraint = try #require(
      node.constraints.first { $0.first.attribute == "width" },
      "the activated width constraint must appear")

    #expect(constraint.first.attribute == "width")
    #expect(constraint.relation == "equal")
    #expect(constraint.constant == 100)
    #expect(constraint.multiplier == 1)
    #expect(constraint.isActive)
    #expect(constraint.first.isTarget)
    #expect(constraint.first.kind == "view")
  }

  @Test(.scenario("scenario.runtime.walker.constant-constraint"))
  func `a constant constraint has an absent, none-kind second item`() throws {
    let view = NSView(frame: .zero)
    view.widthAnchor.constraint(equalToConstant: 42).isActive = true

    let node = ConstraintNode.snapshot(of: view)
    let constraint = try #require(node.constraints.first { $0.first.attribute == "width" })

    #expect(constraint.second.className == nil)
    #expect(constraint.second.kind == "none")
    #expect(constraint.second.attribute == "notAnAttribute")
    #expect(!constraint.second.isTarget)
  }

  @Test(.scenario("scenario.runtime.walker.intrinsic-default"))
  func `a plain view reports no intrinsic metric as -1 on both axes`() {
    let node = ConstraintNode.snapshot(of: NSView(frame: .zero))
    #expect(node.intrinsicContentSize.width == Double(NSView.noIntrinsicMetric))
    #expect(node.intrinsicContentSize.height == Double(NSView.noIntrinsicMetric))
    #expect(node.intrinsicContentSize.width == -1)
    #expect(node.intrinsicContentSize.height == -1)
  }

  @Test(.scenario("scenario.runtime.walker.sizing-defaults"))
  func `a fresh view carries its AppKit-default hugging and compression priorities`() {
    let view = NSView(frame: .zero)
    let node = ConstraintNode.snapshot(of: view)
    #expect(
      node.contentHuggingHorizontal
        == Double(view.contentHuggingPriority(for: .horizontal).rawValue))
    #expect(
      node.contentHuggingVertical
        == Double(view.contentHuggingPriority(for: .vertical).rawValue))
    #expect(
      node.compressionResistanceHorizontal
        == Double(view.contentCompressionResistancePriority(for: .horizontal).rawValue))
    #expect(
      node.compressionResistanceVertical
        == Double(view.contentCompressionResistancePriority(for: .vertical).rawValue))
    #expect(
      node.translatesAutoresizingMaskIntoConstraints
        == view.translatesAutoresizingMaskIntoConstraints)
  }

  @Test(.scenario("scenario.runtime.walker.ancestor-touch"))
  func `an ancestor-held constraint touching the target is collected`() throws {
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
    let child = NSView(frame: .zero)
    child.translatesAutoresizingMaskIntoConstraints = false
    parent.addSubview(child)
    // Held by the parent, but it touches the child (first item).
    let pin = child.leadingAnchor.constraint(equalTo: parent.leadingAnchor, constant: 8)
    pin.isActive = true

    let node = ConstraintNode.snapshot(of: child)
    let touching = try #require(
      node.constraints.first { $0.first.attribute == "leading" && $0.first.isTarget },
      "the parent-held constraint referencing the child must be collected")
    #expect(touching.constant == 8)
    #expect(touching.second.attribute == "leading")
    #expect(touching.second.kind == "view")
    #expect(!touching.second.isTarget)
  }

  @Test(.scenario("scenario.runtime.walker.ancestor-touch"))
  func `an ancestor constraint touching only a sibling is excluded`() {
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
    let target = NSView(frame: .zero)
    let sibling = NSView(frame: .zero)
    for sub in [target, sibling] {
      sub.translatesAutoresizingMaskIntoConstraints = false
      parent.addSubview(sub)
    }
    // Touches the sibling and the parent — never the target.
    sibling.topAnchor.constraint(equalTo: parent.topAnchor).isActive = true

    let node = ConstraintNode.snapshot(of: target)
    // No collected constraint may reference the target's sibling on either side.
    let siblingClass = NSStringFromClass(object_getClass(sibling)!)
    #expect(!node.constraints.contains { $0.first.className == siblingClass })
    #expect(!node.constraints.contains { $0.second.className == siblingClass })
  }

  @Test(.scenario("scenario.runtime.walker.constraint-dedup"))
  func `a constraint reachable from both view and ancestor appears once`() {
    let parent = NSView(frame: NSRect(x: 0, y: 0, width: 200, height: 200))
    let child = NSView(frame: .zero)
    child.translatesAutoresizingMaskIntoConstraints = false
    parent.addSubview(child)
    // A child<->parent constraint is held by the parent and references the child.
    let pin = child.widthAnchor.constraint(equalTo: parent.widthAnchor)
    pin.isActive = true

    let node = ConstraintNode.snapshot(of: child)
    let widthOnTarget = node.constraints.filter {
      $0.first.attribute == "width" && $0.first.isTarget && $0.second.attribute == "width"
    }
    #expect(widthOnTarget.count == 1, "the shared constraint must be deduplicated")
  }

  @Test(.scenario("scenario.runtime.walker.constraint-real-class"))
  func `className is the runtime class name, not the static type`() throws {
    let view = NSView(frame: .zero)
    view.widthAnchor.constraint(equalToConstant: 10).isActive = true

    let node = ConstraintNode.snapshot(of: view)
    let constraint = try #require(node.constraints.first { $0.first.isTarget })
    // The runtime ISA of the view, via object_getClass — what the snapshot stores.
    #expect(constraint.first.className == NSStringFromClass(object_getClass(view)!))
  }

  @Test
  func `the height and greaterThanOrEqual string maps decompose correctly`() {
    // The named cases above pin width/leading + equal; this pins the height
    // attribute and the greaterThanOrEqual relation arms of the two string maps.
    let view = NSView(frame: .zero)
    view.heightAnchor.constraint(greaterThanOrEqualToConstant: 5).isActive = true
    let node = ConstraintNode.snapshot(of: view)
    let constraint = node.constraints.first { $0.first.attribute == "height" }
    #expect(constraint?.relation == "greaterThanOrEqual")
  }

  @Test
  func `the snapshot is Codable plain data that round-trips`() throws {
    let view = NSView(frame: .zero)
    view.widthAnchor.constraint(equalToConstant: 100).isActive = true
    let node = ConstraintNode.snapshot(of: view)

    let data = try JSONEncoder().encode(node)
    let decoded = try JSONDecoder().decode(ConstraintNode.self, from: data)
    #expect(decoded.intrinsicContentSize.width == node.intrinsicContentSize.width)
    #expect(decoded.constraints.count == node.constraints.count)
    #expect(decoded.constraints.first?.constant == node.constraints.first?.constant)
  }
}
