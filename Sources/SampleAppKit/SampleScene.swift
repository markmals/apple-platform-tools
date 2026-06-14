import AppKit

// SPEC: domain.uitool.server
/// The known-geometry oracle the live-runtime cluster is verified against — a tiny
/// AppKit scene with a **pinned** layout, built on the main thread. It is the
/// fixture every live verb is checked against, so its geometry is a contract: each
/// element exists to exercise a walker field the cheap-read verbs project (real
/// runtime class, a visual-effect material, a flipped container's coordinate flip,
/// a constraint count, a label's text + font, an unbacked layer, a panel, a nested
/// child window). It is a test-support target, never a shipped product; later it
/// becomes the launchable injection harness.
///
/// The exact pixel values here ARE the tests' source of truth — assert against
/// `Known`, not against magic numbers.
public enum SampleScene {

  /// The pinned facts the tests assert against.
  public enum Known {
    public static let mainTitle = "SampleAppKit"
    public static let childTitle = "SampleAppKit Inspector"
    public static let panelIdentifier = "inspectorPanel"

    public static let sidebarIdentifier = "sidebar"
    public static let sidebarMaterial = "sidebar"  // NSVisualEffectView.Material.sidebar

    public static let greetingIdentifier = "greeting"
    public static let greetingText = "Hello"
    public static let greetingFontSize: CGFloat = 13

    public static let flippedBoxIdentifier = "flippedBox"
    public static let flippedChildWidth: CGFloat = 200

    public static let plainIdentifier = "plain"

    public static let mainContentSize = CGSize(width: 400, height: 300)
  }

  /// Build the oracle's windows. The caller orders them front (so `NSApp.windows`
  /// sees them) and tears them down; the child window is attached to the main
  /// window, so it is nested rather than a separate root.
  @MainActor
  public static func make() -> SampleWindows {
    let main = makeMainWindow()
    let panel = makePanel()
    let child = makeChildWindow()
    main.addChildWindow(child, ordered: .above)
    return SampleWindows(main: main, panel: panel, child: child)
  }

  // MARK: - Windows

  @MainActor
  private static func makeMainWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(origin: .zero, size: Known.mainContentSize),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false)
    window.title = Known.mainTitle
    window.contentView = makeContentView()
    return window
  }

  @MainActor
  private static func makePanel() -> NSPanel {
    let panel = NSPanel(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 150),
      styleMask: [.titled, .closable, .utilityWindow],
      backing: .buffered,
      defer: false)
    panel.identifier = NSUserInterfaceItemIdentifier(Known.panelIdentifier)
    return panel
  }

  @MainActor
  private static func makeChildWindow() -> NSWindow {
    let window = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 200, height: 150),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false)
    window.title = Known.childTitle
    return window
  }

  // MARK: - The main window's content view

  /// A non-flipped content view holding: a sidebar visual-effect view, a greeting
  /// label, a flipped container with one width-constrained child, and a plain
  /// unbacked view.
  @MainActor
  private static func makeContentView() -> NSView {
    let content = NSView(frame: NSRect(origin: .zero, size: Known.mainContentSize))

    let sidebar = NSVisualEffectView(frame: NSRect(x: 0, y: 0, width: 120, height: 300))
    sidebar.material = .sidebar
    sidebar.identifier = NSUserInterfaceItemIdentifier(Known.sidebarIdentifier)

    let greeting = NSTextField(labelWithString: Known.greetingText)
    greeting.frame = NSRect(x: 130, y: 260, width: 200, height: 20)
    greeting.font = NSFont.systemFont(ofSize: Known.greetingFontSize)
    greeting.identifier = NSUserInterfaceItemIdentifier(Known.greetingIdentifier)

    let flippedBox = FlippedBox(frame: NSRect(x: 130, y: 0, width: 260, height: 250))
    flippedBox.identifier = NSUserInterfaceItemIdentifier(Known.flippedBoxIdentifier)
    let constrained = NSView(frame: .zero)
    constrained.translatesAutoresizingMaskIntoConstraints = false
    flippedBox.addSubview(constrained)
    constrained.widthAnchor.constraint(equalToConstant: Known.flippedChildWidth).isActive = true

    // A plain layer-less view: NSView.layer is nil unless wantsLayer is set, so the
    // walker reports layer == nil (not a present:false stand-in).
    let plain = NSView(frame: NSRect(x: 130, y: 220, width: 100, height: 20))
    plain.identifier = NSUserInterfaceItemIdentifier(Known.plainIdentifier)

    content.addSubview(sidebar)
    content.addSubview(greeting)
    content.addSubview(flippedBox)
    content.addSubview(plain)
    return content
  }
}

/// A flipped container, so the walker's coordinate-flip path is exercised by a real
/// `isFlipped == true` node, not only the default bottom-left.
private final class FlippedBox: NSView {
  override var isFlipped: Bool { true }
}

// SPEC: domain.uitool.server
/// A handle to the oracle's live windows so a test can order them front (making
/// them visible to `NSApp.windows`, which the walker reads) and tear them down.
@MainActor
public final class SampleWindows {
  public let main: NSWindow
  public let panel: NSWindow
  public let child: NSWindow

  fileprivate init(main: NSWindow, panel: NSWindow, child: NSWindow) {
    self.main = main
    self.panel = panel
    self.child = child
  }

  /// Order the roots on screen. The child window rides along under the main window
  /// (it was attached via `addChildWindow`).
  public func orderFront() {
    main.makeKeyAndOrderFront(nil)
    panel.orderFront(nil)
  }

  /// Detach the child and order every window out — leaving `NSApp.windows` as it
  /// was before `orderFront`.
  public func teardown() {
    main.removeChildWindow(child)
    child.orderOut(nil)
    panel.orderOut(nil)
    main.orderOut(nil)
  }
}
