import Foundation
import ItchyCore
import MCP
import Network
import Testing

@testable import ItchyServices

/// A running server on an ephemeral port, with a client that can reach it.
///
/// Shared by the two end-to-end suites. Ephemeral, so the tests neither collide
/// with a running Itchy nor with each other.
internal struct MCPServerFixture: ~Copyable {
  internal let root: URL
  internal let store: PadStore
  internal let host: MCPServerHost
  internal let token: MCPToken
  internal let port: Int

  internal var endpoint: URL {
    URL(string: "http://127.0.0.1:\(port)/mcp") ?? URL(fileURLWithPath: "/")
  }

  internal static func make(presence: any PadPresence = NoPadsOpen()) async throws -> Self {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-mcp-host-\(UUID().uuidString)")
    let store = PadStore(layout: PadStorageLayout(root: root))
    await store.load()
    let token = MCPToken.generate()
    let host = MCPServerHost(
      service: MCPService(
        store: store, writer: StorePadWriter(store: store), presence: presence, client: "test"),
      token: token,
      port: 0)
    let port = try await host.start()
    return MCPServerFixture(root: root, store: store, host: host, token: token, port: port)
  }

  internal func client(token presented: String? = nil) -> (Client, HTTPClientTransport) {
    let value = presented ?? token.value
    let transport = HTTPClientTransport(
      endpoint: endpoint,
      streaming: false,
      requestModifier: { request in
        var request = request
        request.setValue("Bearer \(value)", forHTTPHeaderField: "Authorization")
        return request
      })
    return (Client(name: "test-agent", version: "1"), transport)
  }

  internal func exposedPad(named name: String, text: String = "") async throws -> PadMetadata {
    let pad = try await store.createPad(name: name)
    try await store.setExposedToMCP(pad.id, true)
    guard !text.isEmpty else { return pad }
    await store.stage(PadContent.plainText(text), for: pad.id, origin: .user)
    try await store.flush(pad.id)
    return pad
  }
}

internal func tearDown(_ fixture: borrowing MCPServerFixture) async {
  await fixture.host.stop()
  try? FileManager.default.removeItem(at: fixture.root)
}

/// The text an agent actually sees, out of the SDK's content envelope.
internal func text(of content: [Tool.Content]) -> String {
  content.compactMap { item in
    guard case .text(let text, _, _) = item else { return nil }
    return text
  }
  .joined(separator: "\n")
}

/// A bare POST, for the cases that are about the wire rather than the protocol.
internal func post(
  to endpoint: URL, bearer: String?, body: Data = Data(#"{"jsonrpc":"2.0"}"#.utf8),
  headers: [String: String] = [:]
) async throws -> (Int, Data) {
  var request = URLRequest(url: endpoint)
  request.httpMethod = "POST"
  request.httpBody = body
  request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
  request.setValue("application/json", forHTTPHeaderField: "Content-Type")
  if let bearer { request.setValue("Bearer \(bearer)", forHTTPHeaderField: "Authorization") }
  for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
  let (data, response) = try await URLSession.shared.data(for: request)
  return ((response as? HTTPURLResponse)?.statusCode ?? 0, data)
}

/// Whether anything answers on an address and port, within a bound.
/// How long a connection attempt is given before it counts as nothing
/// answering. Bounded, because "nothing is listening" is otherwise a test that
/// waits out a default connection timeout, which is measured in minutes.
private let connectLimit: Duration = .milliseconds(750)

internal func canConnect(host: String, port: Int) async -> Bool {
  await withCheckedContinuation { (continuation: CheckedContinuation<Bool, Never>) in
    let once = ConnectOnce(continuation)
    let connection = NWConnection(
      host: NWEndpoint.Host(host),
      port: NWEndpoint.Port(rawValue: UInt16(port)) ?? .any,
      using: .tcp)
    connection.stateUpdateHandler = { state in
      switch state {
      case .ready: once.finish(true)
      case .failed, .cancelled, .waiting: once.finish(false)
      default: break
      }
    }
    connection.start(queue: .global())
    Task {
      try? await Task.sleep(for: connectLimit)
      once.finish(false)
      connection.cancel()
    }
  }
}

/// Every IPv4 address this machine has that is not loopback.
internal func nonLoopbackAddresses() -> [String] {
  var addresses: [String] = []
  var head: UnsafeMutablePointer<ifaddrs>?
  guard getifaddrs(&head) == 0, let first = head else { return [] }
  defer { freeifaddrs(head) }
  for interface in sequence(first: first, next: { $0.pointee.ifa_next }) {
    guard let raw = interface.pointee.ifa_addr, raw.pointee.sa_family == UInt8(AF_INET) else {
      continue
    }
    var buffer = [CChar](repeating: 0, count: Int(NI_MAXHOST))
    let named = getnameinfo(
      raw, socklen_t(raw.pointee.sa_len), &buffer, socklen_t(buffer.count), nil, 0, NI_NUMERICHOST)
    guard named == 0 else { continue }
    let address = String(cString: buffer)
    guard address != "127.0.0.1", !address.hasPrefix("169.254.") else { continue }
    addresses.append(address)
  }
  return Array(Set(addresses))
}

/// A presence that says every pad is on screen, for the refusal case.
internal struct EverythingOpen: PadPresence {
  internal func isOpen(_ id: PadID) async -> Bool { true }
}

private final class ConnectOnce: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Bool, Never>?

  init(_ continuation: CheckedContinuation<Bool, Never>) {
    self.continuation = continuation
  }

  func finish(_ value: Bool) {
    lock.lock()
    let pending = continuation
    continuation = nil
    lock.unlock()
    pending?.resume(returning: value)
  }
}
