import Foundation

/// The two wire formats this thing sits between, as values (§11.1).
///
/// Both are framing rather than protocol: neither knows what an MCP message
/// means, only where one ends. That distinction is the shim's whole reason for
/// existing, and keeping the framing in value types is what lets it be tested
/// without a server on one side and a client on the other.
public enum StdioFraming {
  /// MCP over stdio is one JSON message per line. Splits a buffer into whole
  /// lines and hands back whatever is left over, so a message arriving in two
  /// reads is not two messages.
  public static func messages(in buffer: inout Data) -> [Data] {
    var found: [Data] = []
    while let newline = buffer.firstIndex(of: 0x0A) {
      let line = buffer[buffer.startIndex..<newline]
      buffer = Data(buffer[buffer.index(after: newline)...])
      let trimmed = trimmingCarriageReturn(Data(line))
      guard !trimmed.isEmpty else { continue }
      found.append(trimmed)
    }
    return found
  }

  /// One message, terminated. The newline is the frame.
  public static func line(_ message: Data) -> Data {
    var out = message
    out.append(0x0A)
    return out
  }

  private static func trimmingCarriageReturn(_ data: Data) -> Data {
    guard data.last == 0x0D else { return data }
    return data.dropLast()
  }
}

/// Pulls the JSON-RPC messages out of a `text/event-stream` body.
///
/// The server answers a request with SSE rather than a plain body, so this is
/// not optional. It reads only what it needs — the `data:` field — and ignores
/// `id:`, `event:` and `retry:`, because resumption belongs to a client that
/// holds a connection open and the shim holds nothing.
public enum ServerSentEvents {
  public static func payloads(in body: Data) -> [Data] {
    let text = String(bytes: body, encoding: .utf8) ?? ""
    var payloads: [Data] = []
    // An event may spread its data over several `data:` lines, which are joined
    // with newlines; a blank line ends the event.
    var current: [String] = []
    for line in text.components(separatedBy: "\n") {
      let line = line.hasSuffix("\r") ? String(line.dropLast()) : line
      if line.isEmpty {
        appendEvent(&payloads, from: &current)
        continue
      }
      guard line.hasPrefix("data:") else { continue }
      var value = String(line.dropFirst("data:".count))
      if value.hasPrefix(" ") { value.removeFirst() }
      current.append(value)
    }
    appendEvent(&payloads, from: &current)
    return payloads
  }

  private static func appendEvent(_ payloads: inout [Data], from current: inout [String]) {
    defer { current.removeAll() }
    let joined = current.joined(separator: "\n")
    // The priming event the transport sends for resumability has empty data.
    guard !joined.isEmpty else { return }
    payloads.append(Data(joined.utf8))
  }
}

/// What to do with one HTTP response, given its status and content type.
///
/// A decision rather than a branch inside the request loop, because "202 means
/// say nothing" is the sort of rule that is obvious until a client hangs
/// waiting for a reply to a notification.
public enum ResponseHandling: Sendable, Equatable {
  case forwardJSON
  case forwardEventStream
  case silent
  case failed(status: Int)

  public static func decide(status: Int, contentType: String?) -> ResponseHandling {
    guard (200..<300).contains(status) else { return .failed(status: status) }
    guard status != 202 else { return .silent }
    let type = (contentType ?? "").lowercased()
    if type.contains("text/event-stream") { return .forwardEventStream }
    if type.contains("application/json") { return .forwardJSON }
    // A 200 with no body and nothing to say — a DELETE acknowledgement.
    return .silent
  }
}
