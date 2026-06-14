import AgentCLI
import Dispatch
import Foundation
import UIToolCore

// SPEC: domain.uitool.ipc
/// Marshal a unit of work onto the target's main thread under a bounded timeout.
/// AppKit reads are main-thread-only, and a busy or modal main thread must not
/// hang the inspector — a hop that exceeds the bound returns `nil` so the caller
/// emits `TIMEOUT` ([[domain.uitool.ipc]] threading: the fixed ≈500 ms bound).
public enum MainThreadHop {
  /// The fixed per-hop bound for v1 (not per-request configurable).
  public static let bound: DispatchTimeInterval = .milliseconds(500)

  /// Run `work` on the main thread and return its result, or `nil` if the main
  /// thread did not answer within `timeout`. Called inline when already on main.
  public static func run<T: Sendable>(
    timeout: DispatchTimeInterval = bound, _ work: @escaping @Sendable () -> T
  ) -> T? {
    if Thread.isMainThread { return work() }
    let box = ResultBox<T>()
    let semaphore = DispatchSemaphore(value: 0)
    DispatchQueue.main.async {
      box.value = work()
      semaphore.signal()
    }
    guard semaphore.wait(timeout: .now() + timeout) == .success else { return nil }
    return box.value
  }
}

/// A one-shot result carrier across the hop. `@unchecked Sendable`: it is written
/// once on main and read once on the waiting thread, ordered by the semaphore.
private final class ResultBox<T>: @unchecked Sendable {
  var value: T?
}

// SPEC: domain.uitool.server
/// The handler the boot dylib hands `SocketServer`: each request runs through
/// `RequestHandler` on the main thread under the bounded hop; a hop that times out
/// becomes a `TIMEOUT` response rather than a hang. This is the one place transport
/// (background thread) and the AppKit reads (main thread) are bridged.
public func makeBoundedHandler(epoch: Int) -> @Sendable (WireRequest) -> String {
  { request in
    let line: String? = MainThreadHop.run {
      MainActor.assumeIsolated {
        (try? RequestHandler.handle(request, epoch: epoch)) ?? timeoutLine(id: request.id)
      }
    }
    return line ?? timeoutLine(id: request.id)
  }
}

/// A `TIMEOUT` (exit 7) response line for a request the main thread could not
/// answer in time, or an encode that failed.
private func timeoutLine(id: Int) -> String {
  let error = WireError(
    code: "TIMEOUT",
    message: "the target main thread did not answer within the bound",
    recover: "retry once the target is idle (dismiss any modal)")
  let response = WireResponse<Capture>.failure(id: id, error)
  return (try? Output.line(response)) ?? "{\"v\":1,\"id\":\(id),\"ok\":false}"
}
