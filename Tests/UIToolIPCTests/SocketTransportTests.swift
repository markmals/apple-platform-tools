import AgentCLI
import Foundation
import SampleAppKit
import TestSupport
import Testing
import UIToolCore
import UIToolIPC
import UIToolServer

// SPEC: domain.uitool.ipc
//
// The socket transport end-to-end over a loopback — no injection. A SocketServer
// binds a temp unix socket and an IPCClient connects from the same process: the
// request/response framing, the ping handshake (incl. a schema skew), and a
// refused connect are all deterministic. The final test wires the REAL bounded
// handler (RequestHandler on the main thread) against the SampleAppKit oracle, so
// the full server transport is proven on a stock Mac.

private func tempSocketPath() -> String {
  "/tmp/uitool-test-\(UUID().uuidString.prefix(8)).sock"
}

/// A canned handler: a fixed ping/capture, so the transport is exercised without
/// touching AppKit or the main thread.
private func cannedHandler(epoch: Int, schema: String = Schema.version)
  -> @Sendable (WireRequest) -> String
{
  { request in
    if request.op == "ping" {
      return
        (try? Output.line(
          WireResponse<Ping>.success(id: request.id, Ping(schemaVersion: schema, epoch: epoch))))
        ?? ""
    }
    return
      (try? Output.line(
        WireResponse<Capture>.success(id: request.id, Capture(epoch: epoch, windows: [])))) ?? ""
  }
}

@Suite(.spec("domain.uitool.ipc"))
struct SocketTransportTests {

  @Test func `a ping and a read round-trip over the socket`() throws {
    let path = tempSocketPath()
    let server = SocketServer(socketPath: path, handler: cannedHandler(epoch: 42))
    try server.start()
    defer { server.stop() }

    let client = try IPCClient.connect(socketPath: path)
    defer { client.close() }

    let ping = try client.handshake()
    #expect(ping.epoch == 42)
    #expect(ping.schemaVersion == Schema.version)

    let capture = try client.fetchCapture()
    #expect(capture.epoch == 42)
  }

  @Test func `connecting with no live session is NOT_ATTACHED`() {
    let path = tempSocketPath()  // nothing is listening
    #expect(throws: UIToolError.notAttached) {
      _ = try IPCClient.connect(socketPath: path)
    }
  }

  @Test func `a schema skew on the handshake is SCHEMA_MISMATCH (exit 8)`() throws {
    let path = tempSocketPath()
    let server = SocketServer(socketPath: path, handler: cannedHandler(epoch: 1, schema: "9.9.9"))
    try server.start()
    defer { server.stop() }

    let client = try IPCClient.connect(socketPath: path)
    defer { client.close() }

    do {
      try client.handshake()
      Issue.record("expected a schema mismatch")
    } catch let error as UIToolError {
      #expect(error.code == "SCHEMA_MISMATCH")
      #expect(error.exitCode == 8)
    }
  }

  @Test func `two requests reuse one connection in order`() throws {
    let path = tempSocketPath()
    let server = SocketServer(socketPath: path, handler: cannedHandler(epoch: 5))
    try server.start()
    defer { server.stop() }

    let client = try IPCClient.connect(socketPath: path)
    defer { client.close() }

    #expect(try client.handshake().epoch == 5)
    #expect(try client.fetchCapture().epoch == 5)  // a second round-trip on the same connection
  }

  // MARK: - the real bounded handler against the oracle

  @MainActor
  @Test func `a live read over the socket returns the oracle's window forest`() async throws {
    let scene = SampleScene.make()
    scene.orderFront()
    defer { scene.teardown() }

    let path = tempSocketPath()
    let server = SocketServer(socketPath: path, handler: makeBoundedHandler(epoch: 11))
    try server.start()
    defer { server.stop() }

    // Run the client off the main actor so the main thread stays free to service
    // the server's bounded main-thread hop (the AppKit read).
    let capture = try await Task.detached {
      let client = try IPCClient.connect(socketPath: path)
      defer { client.close() }
      try client.handshake()
      return try client.fetchCapture()
    }.value

    #expect(capture.epoch == 11)
    #expect(capture.windows.contains { $0.title == SampleScene.Known.mainTitle })
  }

  @Test func `the bounded hop runs work inline when already on the main thread`() async {
    let value = await MainActor.run { MainThreadHop.run { 7 } }
    #expect(value == 7)
  }
}
