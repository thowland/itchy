import Foundation

/// Serialises a response back onto the wire (§11.1).
///
/// Performs nothing and decides nothing beyond the wire format itself: what to
/// answer is the SDK's or `MCPAuthorization`'s, and this turns an answer into
/// bytes. Split from the listener so that the framing is testable as a string
/// comparison rather than by reading a socket.
public enum HTTPResponseWriter {
  /// Whether the connection is reusable after this response.
  ///
  /// An enumeration rather than a `Bool` because the listener acts on it — a
  /// stream ends by closing the connection, an ordinary response does not — and
  /// a Boolean at that call site reads as a flag rather than as the decision it
  /// is.
  public enum Continuation: Sendable, Equatable {
    case keepAlive
    case close
  }

  /// The status line and headers, with a body length stated.
  public static func head(
    status: Int, headers: [String: String], bodyLength: Int?, continuation: Continuation
  ) -> Data {
    var lines = ["HTTP/1.1 \(status) \(reason(for: status))"]
    var all = headers
    if let bodyLength {
      all["Content-Length"] = String(bodyLength)
    }
    all["Connection"] = continuation == .close ? "close" : "keep-alive"
    for name in all.keys.sorted() {
      lines.append("\(name): \(all[name] ?? "")")
    }
    return Data((lines.joined(separator: "\r\n") + "\r\n\r\n").utf8)
  }

  /// A complete response, head and body together.
  public static func response(
    status: Int, headers: [String: String] = [:], body: Data? = nil,
    continuation: Continuation = .keepAlive
  ) -> Data {
    var data = head(
      status: status, headers: headers, bodyLength: body?.count ?? 0, continuation: continuation)
    if let body { data.append(body) }
    return data
  }

  /// The head of a streaming response. No `Content-Length`: the body's end is
  /// the connection's end, which is what an SSE client expects.
  public static func streamHead(status: Int, headers: [String: String]) -> Data {
    head(status: status, headers: headers, bodyLength: nil, continuation: .close)
  }

  /// A JSON-RPC error body for a refusal made before the SDK is involved.
  ///
  /// Shaped like the SDK's own error responses so that a client parses a
  /// rejected credential the same way it parses a rejected method, rather than
  /// receiving prose where it expected JSON.
  public static func jsonRPCError(code: Int, message: String) -> Data {
    let body: [String: Any] = [
      "jsonrpc": "2.0",
      "error": ["code": code, "message": message],
      "id": NSNull(),
    ]
    return (try? JSONSerialization.data(withJSONObject: body)) ?? Data()
  }

  internal static func reason(for status: Int) -> String {
    reasons[status] ?? "Status \(status)"
  }

  /// A table rather than a switch, because it is a table: a status has a phrase
  /// and there is no decision between them.
  private static let reasons: [Int: String] = [
    200: "OK",
    202: "Accepted",
    400: "Bad Request",
    401: "Unauthorized",
    403: "Forbidden",
    404: "Not Found",
    405: "Method Not Allowed",
    409: "Conflict",
    411: "Length Required",
    413: "Content Too Large",
    421: "Misdirected Request",
    431: "Request Header Fields Too Large",
    500: "Internal Server Error",
    503: "Service Unavailable",
    505: "HTTP Version Not Supported",
  ]
}
