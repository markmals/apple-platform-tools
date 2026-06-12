import AgentCLI
import RuntimeKit

// SPEC: command.uitool.windows
/// One window's record for the `windows` verb — a window-root projection that is
/// deliberately **not** a view node. It carries the four base node fields (`node`,
/// `parent`, `class`, `frame`) plus three **window-only** facts — `title`, `key`,
/// `main` — and nothing view-relative: a window root has no enclosing view, so
/// `frameTopLeft` / `isFlipped` / `hidden` / … do not apply and are absent. The
/// `frame` is the window's **screen-coordinate** `NSWindow.frame` at 1 dp, and the
/// `node` id is the bare window root `<epoch>:w<n>`, never its `…/cv` content view.
public struct WindowRecord: Sendable, Codable {
  /// The window root's node id — `"<epoch>:w<n>"`.
  public let node: String
  /// Always `null`: a top-level window root has no parent.
  public let parent: String?
  /// The window's real runtime class (`NSWindow`, `NSPanel`, a private subclass).
  public let `class`: String
  /// `NSWindow.title`, when set.
  public let title: String?
  /// `NSWindow.frame`, screen coordinates (bottom-left origin), 1 dp.
  public let frame: Rect
  /// `true` when this is the application's key window.
  public let key: Bool
  /// `true` when this is the application's main window.
  public let main: Bool

  init(_ window: WindowSnapshot, id: NodeID) {
    self.node = id.stringValue
    self.parent = nil
    self.class = window.runtimeClass
    self.title = window.title
    self.frame = Rect(
      x: stableRounded(window.frame.x, places: 1),
      y: stableRounded(window.frame.y, places: 1),
      width: stableRounded(window.frame.width, places: 1),
      height: stableRounded(window.frame.height, places: 1))
    self.key = window.isKey
    self.main = window.isMain
  }

  private enum CodingKeys: String, CodingKey {
    case node, parent, `class`, title, frame, key, main
  }

  /// Emit all seven fields **always present** — the windows spec pins the record to
  /// exactly `{node, parent, class, frame, title, key, main}`, so a nil `parent`
  /// (always, for a root) or a nil `title` (an untitled window) encodes as explicit
  /// `null` rather than being dropped the way Swift's synthesized encoder would. The
  /// decode stays synthesized (a null or an absent key both read back as nil).
  public func encode(to encoder: Encoder) throws {
    var container = encoder.container(keyedBy: CodingKeys.self)
    try container.encode(node, forKey: .node)
    try container.encode(parent, forKey: .parent)
    try container.encode(`class`, forKey: .class)
    try container.encode(title, forKey: .title)
    try container.encode(frame, forKey: .frame)
    try container.encode(key, forKey: .key)
    try container.encode(main, forKey: .main)
  }
}
