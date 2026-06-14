import AppKit
import ObjectiveC
import UIToolCore

// SPEC: domain.uitool.registry (deviates: v1 re-walks the live tree per resolution; the weak-map fast path is the documented optimization, deferred)
/// Resolve a [[domain.uitool.node-id]] structural path to its **live** `NSView`, by
/// re-walking the live tree with exactly the mnemonic + z-order-ordinal rule
/// `NodeTree` uses to mint the path ([[domain.uitool.registry]]). The re-walk *is*
/// the staleness gate: a path the live tree no longer carries simply does not
/// resolve, which the caller surfaces as `STALE_NODE` — never a recycled-pointer
/// read. v1 holds no persistent weak map; correctness comes from the re-walk.
@MainActor
enum LiveTreeResolver {

  /// The live view at `structuralPath` (e.g. `w0/cv/sv0/tv0`), or `nil` if any
  /// segment no longer resolves. Mirrors `NodeTree.indexWindow` / `indexSubtree`:
  /// `w<n>` indexes the top-level windows in `NSApp.windows` order, `cv` is the
  /// window's content view, then each `<mnemonic><ordinal>` selects a subview.
  static func resolve(structuralPath: String) -> NSView? {
    let segments = structuralPath.split(separator: "/").map(String.init)
    guard segments.count >= 2, segments[0].hasPrefix("w"),
      segments[1] == StructuralPath.contentView,
      let windowIndex = Int(segments[0].dropFirst())
    else { return nil }

    let topWindows = NSApplication.shared.windows.filter {
      $0.parent == nil && $0.sheetParent == nil
    }
    guard windowIndex < topWindows.count, let contentView = topWindows[windowIndex].contentView
    else { return nil }

    var current = contentView
    for segment in segments.dropFirst(2) {
      guard let next = child(matching: segment, in: current) else { return nil }
      current = next
    }
    return current
  }

  /// The subview matching `<mnemonic><ordinal>`, computing each child's mnemonic
  /// from its **runtime** class and counting per-mnemonic in z-order — the same
  /// assignment `NodeTree.indexSubtree` makes over the snapshot.
  private static func child(matching segment: String, in view: NSView) -> NSView? {
    var ordinals: [String: Int] = [:]
    for child in view.subviews {
      let className = NSStringFromClass(object_getClass(child) ?? type(of: child))
      let mnemonic = StructuralPath.mnemonic(forClass: className)
      let ordinal = ordinals[mnemonic, default: 0]
      ordinals[mnemonic] = ordinal + 1
      if "\(mnemonic)\(ordinal)" == segment { return child }
    }
    return nil
  }
}
