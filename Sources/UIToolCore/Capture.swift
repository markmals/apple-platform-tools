import RuntimeKit

// SPEC: domain.uitool.ipc
/// The offline snapshot envelope the cheap-read MVP reads and the (deferred)
/// injected server writes. A `Capture` is one app's window forest frozen at one
/// `epoch` — the same epoch every minted [[domain.uitool.node-id]] carries, so a
/// captured snapshot and the handles read out of it agree on the staleness gate.
///
/// This is the offline data source's on-disk contract: `uitool windows
/// --snapshot capture.json` decodes a `Capture`, builds a `NodeTree(windows:
/// epoch:)` from it, and runs the read verbs against it with no live process and
/// no socket. The future `UIToolServer` produces the same shape over the wire, so
/// the offline and live sources are interchangeable behind `SnapshotSource`.
public struct Capture: Sendable, Codable {
  /// The session epoch the windows were captured at — seeds `NodeTree`'s epoch and
  /// every node id's `sessionEpoch`.
  public let epoch: Int

  /// The app's top-level windows in `NSApp.windows` order (the `wN` index basis).
  public let windows: [WindowSnapshot]

  public init(epoch: Int, windows: [WindowSnapshot]) {
    self.epoch = epoch
    self.windows = windows
  }
}
