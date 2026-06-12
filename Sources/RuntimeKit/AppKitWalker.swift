import AppKit
import ObjectiveC

// SPEC: domain.runtime.walker
/// The headless macOS view-tree walker: `NSApp` → `NSWindow` → `NSView`, reading
/// the per-node facts into the plain `ViewSnapshot` / `WindowSnapshot` value types
/// — the Swift port of FLEX's `FLEXAppKitWalker`.
///
/// Every entry point is `@MainActor`: AppKit view state is main-thread-only, and
/// reading it off-main is undefined behavior. The walker is the *only* I/O — it
/// reads the live tree on main and immediately decomposes each node into plain
/// data, so the resulting snapshots cross actor and IPC boundaries freely.
///
/// Recursion is depth-bounded and guarded by a visited set keyed on
/// `ObjectIdentifier`, so a cyclic or pathological tree can never overflow the
/// stack. A node still bearing subviews at the depth floor is marked `truncated`,
/// its `children` left empty, while its `childCount` stays truthful.
@MainActor
public enum AppKitWalker {
  /// Snapshot `view` and its subtree, normalizing top-left frames against
  /// `window`'s full frame (titlebar included). Pass the view's window; when it is
  /// `nil`, `frameTopLeft` falls back to the raw `frame`. Recursion is capped at
  /// `maxDepth` levels below `view` (default unbounded). A node at the bound that
  /// still has subviews reports `truncated == true` and omits `children`.
  public static func snapshot(
    view: NSView,
    inWindow window: NSWindow?,
    maxDepth: Int = .max
  ) -> ViewSnapshot {
    var visited: Set<ObjectIdentifier> = []
    return snapshot(of: view, inWindow: window, depth: 0, maxDepth: maxDepth, visited: &visited)
  }

  /// Snapshot every top-level `NSApp` window as a tree root, each with its
  /// `contentView` subtree. A window attached as a sheet or held as a child window
  /// is nested under its parent, so it is skipped here rather than emitted as a
  /// separate root. The key and main windows are identified.
  public static func snapshotApplicationWindows(maxDepth: Int = .max) -> [WindowSnapshot] {
    let app = NSApplication.shared
    let keyWindow = app.keyWindow
    let mainWindow = app.mainWindow

    var seen: Set<ObjectIdentifier> = []
    var result: [WindowSnapshot] = []
    for window in app.windows where window.parent == nil && window.sheetParent == nil {
      result.append(
        windowSnapshot(
          of: window, key: keyWindow, main: mainWindow, maxDepth: maxDepth, seen: &seen))
    }
    return result
  }

  /// The deepest view at `point` (window base coordinates, bottom-left origin),
  /// snapshotted as a single node with its children omitted — the macOS substitute
  /// for touch hit-testing. Returns `nil` if nothing is hit.
  public static func snapshotForHitTest(at point: CGPoint, inWindow window: NSWindow)
    -> ViewSnapshot?
  {
    // `hitTest:` wants the point in the receiver's superview coordinates; the
    // window's root view (the border/theme view) has the window base coordinate
    // system, so a window-base point is correct for it.
    guard let content = window.contentView else { return nil }
    let root = content.superview ?? content
    guard let hit = root.hitTest(point) else { return nil }
    return snapshot(view: hit, inWindow: window, maxDepth: 0)
  }

  // MARK: - Window

  private static func windowSnapshot(
    of window: NSWindow,
    key: NSWindow?,
    main: NSWindow?,
    maxDepth: Int,
    seen: inout Set<ObjectIdentifier>
  ) -> WindowSnapshot {
    seen.insert(ObjectIdentifier(window))
    var visited: Set<ObjectIdentifier> = []
    let contentView = window.contentView.map {
      snapshot(of: $0, inWindow: window, depth: 0, maxDepth: maxDepth, visited: &visited)
    }

    // `childWindows` covers ordered child windows; an attached sheet is tracked
    // separately. Dedup against the app-wide `seen` set so a window captured once
    // never recurs (and a cycle can't loop).
    var children: [WindowSnapshot] = []
    for child in (window.childWindows ?? []) + [window.attachedSheet].compactMap({ $0 })
    where !seen.contains(ObjectIdentifier(child)) {
      children.append(
        windowSnapshot(of: child, key: key, main: main, maxDepth: maxDepth, seen: &seen))
    }

    return WindowSnapshot(
      runtimeClass: NSStringFromClass(object_getClass(window)!),
      title: window.title,
      identifier: window.identifier?.rawValue,
      isKey: window === key,
      isMain: window === main,
      isVisible: window.isVisible,
      isPanel: window is NSPanel,
      frame: Rect(window.frame),
      contentView: contentView,
      childWindows: children)
  }

  // MARK: - View

  private static func snapshot(
    of view: NSView,
    inWindow window: NSWindow?,
    depth: Int,
    maxDepth: Int,
    visited: inout Set<ObjectIdentifier>
  ) -> ViewSnapshot {
    visited.insert(ObjectIdentifier(view))

    let subviews = view.subviews
    let truncated = !subviews.isEmpty && depth >= maxDepth
    let children =
      truncated
      ? []
      : subviews.compactMap { subview -> ViewSnapshot? in
        guard !visited.contains(ObjectIdentifier(subview)) else { return nil }
        return snapshot(
          of: subview, inWindow: window, depth: depth + 1, maxDepth: maxDepth, visited: &visited)
      }

    let effect = view as? NSVisualEffectView

    return ViewSnapshot(
      runtimeClass: NSStringFromClass(object_getClass(view)!),
      superclasses: superclassNames(of: view),
      frame: Rect(view.frame),
      frameTopLeft: Rect(topLeftFrame(of: view, inWindow: window)),
      isFlipped: view.isFlipped,
      hidden: view.isHidden,
      alpha: Double(view.alphaValue),
      identifier: view.identifier?.rawValue,
      text: text(of: view),
      axRole: view.accessibilityRole()?.rawValue,
      font: fontSnapshot(of: view),
      material: effect.map { materialName($0.material) },
      blendingMode: effect.map { blendingModeName($0.blendingMode) },
      layer: view.layer.map { LayerSnapshot.snapshot(of: $0) },
      constraints: ConstraintNode.snapshot(of: view),
      swiftUIBoundary: isSwiftUIBoundary(view),
      childCount: subviews.count,
      truncated: truncated,
      children: children)
  }

  // MARK: - Per-node facts

  /// The runtime class hierarchy from the immediate superclass up to (and
  /// including) `NSObject` — a port of FLEX's `FLEXSuperclassNames`. Starts at the
  /// real ISA's superclass (`object_getClass` first, so a KVO/private subclass is
  /// honored) and stops at `NSObject`.
  private static func superclassNames(of view: NSView) -> [String] {
    var names: [String] = []
    var cls: AnyClass? = class_getSuperclass(object_getClass(view))
    while let current = cls {
      names.append(NSStringFromClass(current))
      if current == NSObject.self { break }
      cls = class_getSuperclass(current)
    }
    return names
  }

  /// The displayed text for the text-bearing view bases (`NSControl.stringValue`,
  /// `NSText.string`), or `nil` when empty — a port of FLEX's `FLEXTextForView`.
  private static func text(of view: NSView) -> String? {
    let text: String?
    if let control = view as? NSControl {
      text = control.stringValue
    } else if let textView = view as? NSText {
      text = textView.string
    } else {
      text = nil
    }
    guard let text, !text.isEmpty else { return nil }
    return text
  }

  /// `true` when the view's class chain contains an `NSHostingView` (SwiftUI's
  /// AppKit host) — a port of FLEX's `FLEXIsSwiftUIBoundary`. The generic
  /// `NSHostingView<Content>` has a mangled Swift name, so the chain is matched by
  /// substring (`object_getClass` up the superclass chain) rather than
  /// `isKindOfClass:` against a single concrete class.
  private static func isSwiftUIBoundary(_ view: NSView) -> Bool {
    var cls: AnyClass? = object_getClass(view)
    while let current = cls {
      if NSStringFromClass(current).contains("NSHostingView") { return true }
      cls = class_getSuperclass(current)
    }
    return false
  }

  /// The font carried by the view (or its cell), decomposed — the walker's half of
  /// FLEX's `+fontForObject:`. The carrier set is "responds to `font`": the view's
  /// own `font`, then its `cell`'s `font`. Each candidate is narrowed to a real
  /// `NSFont` before `FontSnapshot.snapshot(of:)` is handed it, so the snapshot
  /// reader's input is always a genuine font (the spec's deviation from FLEX's raw
  /// `performSelector:` duck-typing).
  private static func fontSnapshot(of view: NSView) -> FontSnapshot? {
    guard let font = fontFromCarrier(view) else { return nil }
    return FontSnapshot.snapshot(of: font)
  }

  /// The `NSFont` read off `carrier` directly, then off its `cell`, or `nil`. Each
  /// read is **guarded by `responds(to:)` first** — faithful to FLEX's
  /// `respondsToSelector:@selector(font)` gate. A bare `value(forKey: "font")` on a
  /// carrier with no `font` accessor (a plain `NSView`) raises an `NSUnknownKey`
  /// ObjC exception, which Swift cannot catch; the `responds(to:)` guard keeps the
  /// accessor from ever being touched on the wrong carrier. The result is narrowed
  /// to a real `NSFont` so the snapshot reader's input is always a genuine font.
  private static func fontFromCarrier(_ carrier: NSObject) -> NSFont? {
    let fontSelector = #selector(getter: NSTextField.font)
    if carrier.responds(to: fontSelector),
      let font = carrier.value(forKey: "font") as? NSFont
    {
      return font
    }
    let cellSelector = #selector(getter: NSControl.cell)
    if carrier.responds(to: cellSelector),
      let cell = carrier.value(forKey: "cell") as? NSObject,
      cell.responds(to: fontSelector),
      let font = cell.value(forKey: "font") as? NSFont
    {
      return font
    }
    return nil
  }

  // MARK: - Coordinate flip

  /// The view normalized to a **top-left-origin** rect relative to the window's
  /// full frame (titlebar included) — a port of FLEX's `+topLeftFrameForView:`.
  ///
  /// The flip is resolved through *AppKit's own* coordinate conversions rather than
  /// by manual y-arithmetic on the raw frame, so per-view `isFlipped` is handled
  /// for free: the view's bounds are converted to window base coordinates, then to
  /// screen coordinates, and finally offset against the window's screen frame. With
  /// no window there is nothing to normalize against, so the raw frame is returned.
  private static func topLeftFrame(of view: NSView, inWindow window: NSWindow?) -> CGRect {
    guard let window else { return view.frame }
    let inWindow = view.convert(view.bounds, to: nil)
    let inScreen = window.convertToScreen(inWindow)
    let windowFrame = window.frame
    let x = inScreen.minX - windowFrame.minX
    let yFromTop = windowFrame.maxY - inScreen.maxY
    return CGRect(x: x, y: yFromTop, width: inScreen.width, height: inScreen.height)
  }

  // MARK: - NSVisualEffectView name maps

  /// `NSVisualEffectView.Material` as a string — a port of FLEX's
  /// `FLEXMaterialName`. An unrecognized raw value falls through to `material(n)`.
  private static func materialName(_ material: NSVisualEffectView.Material) -> String {
    switch material {
    case .titlebar: return "titlebar"
    case .selection: return "selection"
    case .menu: return "menu"
    case .popover: return "popover"
    case .sidebar: return "sidebar"
    case .headerView: return "headerView"
    case .sheet: return "sheet"
    case .windowBackground: return "windowBackground"
    case .hudWindow: return "hudWindow"
    case .fullScreenUI: return "fullScreenUI"
    case .toolTip: return "toolTip"
    case .contentBackground: return "contentBackground"
    case .underWindowBackground: return "underWindowBackground"
    case .underPageBackground: return "underPageBackground"
    // FLEX's `default` arm: the deprecated materials (`appearanceBased`, `light`,
    // `dark`, `mediumLight`, `ultraDark`) and any future raw value fall through to
    // the parameterized `material(n)` form, preserving fidelity. A plain `default`
    // (not `@unknown default`) subsumes the deprecated *known* cases too, matching
    // FLEX, which never enumerated them.
    default: return "material(\(material.rawValue))"
    }
  }

  /// `NSVisualEffectView.BlendingMode` as a string — a port of FLEX's
  /// `FLEXBlendingModeName`. An unrecognized raw value falls through to
  /// `blendingMode(n)`.
  private static func blendingModeName(_ mode: NSVisualEffectView.BlendingMode) -> String {
    switch mode {
    case .behindWindow: return "behindWindow"
    case .withinWindow: return "withinWindow"
    @unknown default: return "blendingMode(\(mode.rawValue))"
    }
  }
}
