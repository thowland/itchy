import Foundation

/// Which MCP session a request belongs to (§11.1).
///
/// A decision, and therefore a value. The SDK's `StatefulHTTPServerTransport`
/// holds exactly one session, so serving two clients at once — the shim and a
/// direct HTTP client, which is precisely what `FR-8.2` asks for — means one
/// transport per session and something to say which. That something is this,
/// and it is tested by handing it a header and a set of names rather than by
/// opening two connections.
public enum MCPSessionRoute: Sendable, Equatable {
  /// Belongs to a session already running.
  case existing(String)
  /// An `initialize` with no session yet: start one.
  case create
  /// Named a session this server does not have — expired, or from a previous
  /// run. `404`, which is what tells a client to initialise again rather than
  /// to retry.
  case unknown(String)
  /// No session named, and not an initialisation. `400`.
  case missing
}

public enum MCPSessionRouter {
  public static func route(
    sessionID: String?, isInitialize: Bool, known: Set<String>
  ) -> MCPSessionRoute {
    if let sessionID, !sessionID.isEmpty {
      // A named session wins even on an initialize: re-initialising an existing
      // session is the transport's error to report, not ours to paper over by
      // quietly starting a second one.
      return known.contains(sessionID) ? .existing(sessionID) : .unknown(sessionID)
    }
    return isInitialize ? .create : .missing
  }
}

/// What a request body is, to the extent the socket layer needs to know.
///
/// The socket must recognise an `initialize` to decide whether to start a
/// session, and that is the whole of its interest in the body. Everything else
/// about the message is the SDK's.
public enum MCPBodyInspector {
  public static func isInitialize(_ body: Data) -> Bool {
    guard !body.isEmpty else { return false }
    guard let json = try? JSONSerialization.jsonObject(with: body) else { return false }
    if let object = json as? [String: Any] {
      return object["method"] as? String == "initialize"
    }
    // A batch counts if any member is an initialize, which is the same reading
    // the SDK takes of a batch containing one.
    if let batch = json as? [[String: Any]] {
      return batch.contains { $0["method"] as? String == "initialize" }
    }
    return false
  }
}
