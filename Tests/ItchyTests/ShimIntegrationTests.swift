import Foundation
import ItchyCore
import ItchyServices
import Testing

@testable import Itchy

/// `FR-8.2`'s acceptance criterion: one client over HTTP and another over the
/// shim, concurrently, both seeing the same pad state.
///
/// This is the criterion that could not be demonstrated for the whole of R1,
/// because the shim did not exist. It launches the real binary as a subprocess
/// and talks to it the way an MCP client does — over its standard input and
/// output, one JSON message per line.
@Suite("The stdio shim, end to end")
struct ShimIntegrationTests {
  /// The shim's two interface constants, retyped rather than imported.
  ///
  /// Linking the shim's library into this bundle made Xcode embed ItchyCore as
  /// a framework inside the *application* — which `NFR-3.5`'s guard caught, and
  /// which is too high a price for two strings. The coupling is enforced by
  /// behaviour instead: rename either of these in the shim and this suite fails,
  /// because the binary will not find the store or the token.
  private let supportRootFlag = "--support-root"
  private let tokenVariable = "ITCHY_TOKEN"

  /// The built shim. Not searched for: `Scripts/test.sh` builds it immediately
  /// before this suite runs, so an absent binary is a broken build rather than
  /// a reason to skip.
  private var shimBinary: URL {
    URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Shim/.build/debug/itchy-mcp")
  }

  private func makeServer() async throws -> (PadStore, MCPServerHost, MCPToken, Int, URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-shim-\(UUID().uuidString)")
    let layout = PadStorageLayout(root: root)
    let store = PadStore(layout: layout)
    await store.load()
    let pad = try await store.createPad(name: "Shared")
    try await store.setExposedToMCP(pad.id, true)
    await store.stage(PadContent.plainText("seen by both"), for: pad.id, origin: .user)
    try await store.flush(pad.id)

    let token = MCPToken.generate()
    let host = MCPServerHost(
      service: MCPService(store: store, writer: StorePadWriter(store: store)),
      token: token, port: 0)
    let port = try await host.start()
    // What the shim reads. This process is alive, so its own identifier is what
    // makes the endpoint look live rather than stale.
    try EndpointStore(layout: layout).write(
      MCPEndpoint(
        port: port,
        processIdentifier: ProcessInfo.processInfo.processIdentifier,
        startedAt: Date()))
    return (store, host, token, port, root)
  }

  /// Speaks MCP to the shim over a pipe and returns the lines it wrote back.
  private func throughShim(
    root: URL, token: MCPToken, messages: [String]
  ) throws -> [[String: Any]] {
    let process = Process()
    process.executableURL = shimBinary
    process.arguments = [supportRootFlag, root.path]
    var environment = ProcessInfo.processInfo.environment
    environment[tokenVariable] = token.value
    process.environment = environment

    let input = Pipe()
    let output = Pipe()
    let errors = Pipe()
    process.standardInput = input
    process.standardOutput = output
    process.standardError = errors
    try process.run()

    for message in messages {
      input.fileHandleForWriting.write(Data((message + "\n").utf8))
    }
    // Closing our end is how a client says it is done; the shim then exits and
    // the read below completes rather than blocking.
    input.fileHandleForWriting.closeFile()

    let data = output.fileHandleForReading.readDataToEndOfFile()
    process.waitUntilExit()
    let complaints = String(
      bytes: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""

    return String(bytes: data, encoding: .utf8)?
      .split(separator: "\n")
      .compactMap { line -> [String: Any]? in
        guard let object = try? JSONSerialization.jsonObject(with: Data(line.utf8)) else {
          Issue.record("the shim wrote something that is not JSON: \(line) \(complaints)")
          return nil
        }
        return object as? [String: Any]
      } ?? []
  }

  private func overHTTP(port: Int, token: MCPToken, body: String, session: String?) async throws
    -> (Int, String, String?) {
    var request = URLRequest(url: URL(fileURLWithPath: "/").absoluteURL)
    request = URLRequest(url: URL(string: "http://127.0.0.1:\(port)/mcp") ?? request.url!)
    request.httpMethod = "POST"
    request.httpBody = Data(body.utf8)
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(token.value)", forHTTPHeaderField: "Authorization")
    if let session { request.setValue(session, forHTTPHeaderField: "Mcp-Session-Id") }
    let (data, response) = try await URLSession.shared.data(for: request)
    let http = response as? HTTPURLResponse
    // The server answers a request with an event stream; the payloads are the
    // `data:` lines. Three lines here rather than a dependency on the shim.
    let text = (String(bytes: data, encoding: .utf8) ?? "")
      .components(separatedBy: "\n")
      .filter { $0.hasPrefix("data:") }
      .joined(separator: "\n")
    return (http?.statusCode ?? 0, text, http?.value(forHTTPHeaderField: "Mcp-Session-Id"))
  }

  private let initialize = #"""
    {"jsonrpc":"2.0","id":1,"method":"initialize","params":{"protocolVersion":"2025-06-18","capabilities":{},"clientInfo":{"name":"test","version":"1"}}}
    """#
  private let readPad = #"""
    {"jsonrpc":"2.0","id":2,"method":"tools/call","params":{"name":"read_pad","arguments":{"pad":"Shared"}}}
    """#

  // MARK: - FR-8.2

  @Test("A client over the shim and a client over HTTP see the same pad", .timeLimit(.minutes(1)))
  func bothTransportsSeeTheSamePad() async throws {
    let (_, host, token, port, root) = try await makeServer()
    defer {
      Task { await host.stop() }
      try? FileManager.default.removeItem(at: root)
    }

    // The HTTP client first, and it stays connected while the shim runs.
    let (status, initialised, session) = try await overHTTP(
      port: port, token: token, body: initialize, session: nil)
    #expect(status == 200)
    #expect(initialised.contains("Itchy"))

    let overStdio = try throughShim(
      root: root, token: token,
      messages: [
        initialize,
        #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
        readPad,
      ])

    // And the HTTP client reads the same pad afterwards, on its own session.
    let (_, httpRead, _) = try await overHTTP(
      port: port, token: token, body: readPad, session: session)

    let shimRead = overStdio.compactMap { message -> String? in
      guard message["id"] as? Int == 2 else { return nil }
      let result = message["result"] as? [String: Any]
      let content = result?["content"] as? [[String: Any]]
      return content?.first?["text"] as? String
    }.first

    #expect(shimRead == "seen by both")
    #expect(httpRead.contains("seen by both"))
    #expect(await host.sessionCount == 2, "two sessions, one per transport")
  }

  @Test("The shim carries the session identifier, so a second call works", .timeLimit(.minutes(1)))
  func keepsTheSession() async throws {
    let (_, host, token, port, root) = try await makeServer()
    _ = port
    defer {
      Task { await host.stop() }
      try? FileManager.default.removeItem(at: root)
    }

    let replies = try throughShim(
      root: root, token: token,
      messages: [
        initialize,
        #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#,
        #"{"jsonrpc":"2.0","id":2,"method":"tools/list"}"#,
        readPad,
      ])

    // Without the session header the second and third calls would be refused
    // with 400, and neither id would come back.
    #expect(replies.contains { $0["id"] as? Int == 2 })
    #expect(replies.contains { $0["id"] as? Int == 3 } == false)
    let tools = replies.first { $0["id"] as? Int == 2 }
    #expect(String(describing: tools ?? [:]).contains("read_pad"))
  }

  /// The notification in the middle must produce no reply, or a client waits
  /// for one that is never coming.
  @Test("A notification draws no reply", .timeLimit(.minutes(1)))
  func notificationIsSilent() async throws {
    let (_, host, token, _, root) = try await makeServer()
    defer {
      Task { await host.stop() }
      try? FileManager.default.removeItem(at: root)
    }

    let replies = try throughShim(
      root: root, token: token,
      messages: [initialize, #"{"jsonrpc":"2.0","method":"notifications/initialized"}"#])

    #expect(replies.count == 1)
    #expect(replies[0]["id"] as? Int == 1)
  }

  /// The failure a person will actually hit, and it has to reach their client's
  /// log rather than vanishing.
  @Test("Without a token the shim refuses to start and says why", .timeLimit(.minutes(1)))
  func refusesWithoutAToken() async throws {
    let (_, host, _, _, root) = try await makeServer()
    defer {
      Task { await host.stop() }
      try? FileManager.default.removeItem(at: root)
    }

    let process = Process()
    process.executableURL = shimBinary
    process.arguments = [supportRootFlag, root.path]
    var environment = ProcessInfo.processInfo.environment
    environment.removeValue(forKey: tokenVariable)
    process.environment = environment
    let errors = Pipe()
    process.standardError = errors
    process.standardOutput = Pipe()
    try process.run()
    let complaint = String(
      bytes: errors.fileHandleForReading.readDataToEndOfFile(), encoding: .utf8) ?? ""
    process.waitUntilExit()

    #expect(process.terminationStatus == 1)
    #expect(complaint.contains(tokenVariable))
  }
}
