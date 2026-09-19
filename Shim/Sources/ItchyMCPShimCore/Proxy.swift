import Foundation

/// Carries messages between stdin/stdout and the loopback endpoint (`FR-8.2`).
///
/// Performs only. What a frame is belongs to `StdioFraming` and
/// `ServerSentEvents`; what a response means belongs to `ResponseHandling`;
/// this opens sockets and moves bytes.
///
/// It holds exactly one thing: the session identifier the server issues at
/// initialisation and requires on everything after it. §11.1 says the shim
/// holds no state, and that is now one word too strong — it holds no *protocol*
/// state, and one identifier it never reads (D-29).
public final class Proxy {
  private let url: URL
  private let token: String
  private let session: URLSession
  private let write: @Sendable (Data) -> Void
  private let complain: @Sendable (String) -> Void
  private var sessionIdentifier: String?

  public init(
    url: URL,
    token: String,
    session: URLSession = .shared,
    write: @escaping @Sendable (Data) -> Void,
    complain: @escaping @Sendable (String) -> Void
  ) {
    self.url = url
    self.token = token
    self.session = session
    self.write = write
    self.complain = complain
  }

  /// Reads until the client closes its end, which is how an MCP client says it
  /// is finished with a subprocess.
  public func run(reading input: FileHandle) async {
    var buffer = Data()
    while true {
      let chunk = input.availableData
      guard !chunk.isEmpty else { return }
      buffer.append(chunk)
      for message in StdioFraming.messages(in: &buffer) {
        await forward(message)
      }
    }
  }

  func forward(_ message: Data) async {
    var request = URLRequest(url: url)
    request.httpMethod = "POST"
    request.httpBody = message
    request.setValue("application/json", forHTTPHeaderField: "Content-Type")
    // Both, because the server answers a request with an event stream and its
    // validator refuses a client that did not say it would accept one.
    request.setValue("application/json, text/event-stream", forHTTPHeaderField: "Accept")
    request.setValue("Bearer \(token)", forHTTPHeaderField: "Authorization")
    if let sessionIdentifier {
      request.setValue(sessionIdentifier, forHTTPHeaderField: "Mcp-Session-Id")
    }

    do {
      let (data, response) = try await session.data(for: request)
      guard let http = response as? HTTPURLResponse else { return }
      if let issued = http.value(forHTTPHeaderField: "Mcp-Session-Id"), !issued.isEmpty {
        sessionIdentifier = issued
      }
      deliver(data, status: http.statusCode, contentType: http.value(forHTTPHeaderField: "Content-Type"))
    } catch {
      complain("itchy-mcp: could not reach \(url.absoluteString) — \(error.localizedDescription)")
      write(StdioFraming.line(Self.transportError("Itchy is not reachable at \(url.absoluteString).")))
    }
  }

  private func deliver(_ data: Data, status: Int, contentType: String?) {
    switch ResponseHandling.decide(status: status, contentType: contentType) {
    case .forwardJSON:
      write(StdioFraming.line(data))
    case .forwardEventStream:
      for payload in ServerSentEvents.payloads(in: data) {
        write(StdioFraming.line(payload))
      }
    case .silent:
      break
    case .failed(let status):
      complain("itchy-mcp: Itchy answered \(status). \(Self.advice(for: status))")
      write(StdioFraming.line(Self.transportError(Self.advice(for: status))))
    }
  }

  static func advice(for status: Int) -> String {
    switch status {
    case 401:
      return "The token was refused. Copy the current one from Itchy → Settings → Agents; "
        + "regenerating it stops the previous one working immediately."
    case 404:
      return "The session is gone. Itchy was probably restarted; restart this client too."
    default:
      return "Itchy refused the request."
    }
  }

  /// A JSON-RPC error with a null id.
  ///
  /// Null rather than the request's, deliberately: echoing the right identifier
  /// would mean parsing the message, and a shim that parses messages is one
  /// change away from interpreting them. The client sees an error either way,
  /// and the useful detail goes to standard error where its log will show it.
  static func transportError(_ message: String) -> Data {
    let body: [String: Any] = [
      "jsonrpc": "2.0",
      "id": NSNull(),
      "error": ["code": -32_001, "message": message],
    ]
    return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
  }
}
