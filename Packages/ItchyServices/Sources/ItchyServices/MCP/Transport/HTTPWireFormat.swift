import Foundation

/// HTTP/1.1 for a single-purpose loopback endpoint (§11.1, D-17).
///
/// D-17 divided the labour: `StatefulHTTPServerTransport` owns protocol
/// conformance, session state and version negotiation, and the socket is ours.
/// Ours therefore includes parsing the request off the wire, and this is that,
/// written as a value so that every case it has to get right — a split header
/// block, a body arriving in three reads, a header line without a colon — is
/// testable by handing it bytes rather than by opening a socket.
///
/// Deliberately a subset. Request line, headers, and a `Content-Length` body;
/// no chunked request bodies, because an MCP client has no reason to send one
/// and accepting a subset on purpose is better than accepting a superset by
/// accident.
public enum HTTPWireFormat {
  /// How much header block will be read before the request is refused. Generous
  /// for a client that sends an `Authorization`, an `Accept` and a session id;
  /// far short of what it would take to exhaust memory.
  public static let maximumHeaderBytes = 64 * 1024

  /// How large a request body may be. A pad is bounded by what a person will
  /// look at, and a tool call carrying eight megabytes of text is a mistake
  /// rather than a use.
  public static let maximumBodyBytes = 8 * 1024 * 1024

  internal static let crlf = Data([0x0D, 0x0A])
  internal static let headerTerminator = Data([0x0D, 0x0A, 0x0D, 0x0A])
}

/// A request read off the wire, before the SDK sees it.
public struct ParsedHTTPRequest: Sendable, Equatable {
  public let method: String
  /// The request target with any query string removed, which is what the SDK's
  /// validators match on.
  public let path: String
  /// Header names as sent. Lookup is case-insensitive through `header(_:)`,
  /// because a client is entitled to send `authorization` in any case it likes.
  public let headers: [String: String]
  public let body: Data
  /// How many bytes of the buffer this request consumed, so the caller can keep
  /// the remainder for the next one.
  public let byteCount: Int

  public init(method: String, path: String, headers: [String: String], body: Data, byteCount: Int) {
    self.method = method
    self.path = path
    self.headers = headers
    self.body = body
    self.byteCount = byteCount
  }

  public func header(_ name: String) -> String? {
    let wanted = name.lowercased()
    return headers.first { $0.key.lowercased() == wanted }?.value
  }
}

/// Why a request could not be read, and what to answer.
///
/// An enumeration with a status rather than a `Bool` and a guess: each of these
/// has a different correct answer, and a connection that is refused with the
/// wrong code is a client that retries forever.
public enum HTTPParseFailure: Error, Sendable, Equatable {
  case malformedRequestLine
  case unsupportedVersion(String)
  case malformedHeader(String)
  case headersTooLarge
  case bodyTooLarge
  case chunkedBodyUnsupported
  case invalidContentLength(String)

  public var statusCode: Int {
    switch self {
    case .malformedRequestLine, .malformedHeader, .invalidContentLength: 400
    case .unsupportedVersion: 505
    case .headersTooLarge: 431
    case .bodyTooLarge: 413
    case .chunkedBodyUnsupported: 411
    }
  }

  public var reason: String {
    switch self {
    case .malformedRequestLine: "The request line could not be read."
    case .unsupportedVersion(let version): "HTTP version '\(version)' is not supported."
    case .malformedHeader(let line): "Header line '\(line)' has no colon."
    case .headersTooLarge: "The header block is larger than this server accepts."
    case .bodyTooLarge: "The request body is larger than this server accepts."
    case .chunkedBodyUnsupported: "A Content-Length is required; chunked bodies are not read."
    case .invalidContentLength(let value): "Content-Length '\(value)' is not a length."
    }
  }
}

/// What a parse attempt produced.
public enum HTTPParseOutcome: Sendable, Equatable {
  /// Not enough bytes yet. The caller reads more and asks again.
  case incomplete
  case complete(ParsedHTTPRequest)
  case failed(HTTPParseFailure)
}

/// Parses one request out of a buffer that may hold part of it, all of it, or
/// more than one.
///
/// Decides; never reads. The socket hands it bytes and it says what they mean,
/// which is what lets the whole wire format be tested without a network.
public enum HTTPRequestParser {
  public static func parse(_ buffer: Data) -> HTTPParseOutcome {
    guard let terminator = range(of: HTTPWireFormat.headerTerminator, in: buffer) else {
      return buffer.count > HTTPWireFormat.maximumHeaderBytes ? .failed(.headersTooLarge) : .incomplete
    }
    let headerBlock = buffer[buffer.startIndex..<terminator.lowerBound]
    guard headerBlock.count <= HTTPWireFormat.maximumHeaderBytes else {
      return .failed(.headersTooLarge)
    }
    let bodyStart = terminator.upperBound

    // Failable rather than lossy: a header block that is not UTF-8 is not a
    // request this endpoint can serve, and replacing the offending bytes would
    // turn it into one that looks servable and is not.
    guard let block = String(bytes: headerBlock, encoding: .utf8) else {
      return .failed(.malformedRequestLine)
    }
    var lines = block.components(separatedBy: "\r\n")
    guard !lines.isEmpty else { return .failed(.malformedRequestLine) }
    let requestLine = lines.removeFirst()

    switch start(requestLine) {
    case .failure(let failure):
      return .failed(failure)
    case .success(let start):
      return complete(start: start, headerLines: lines, buffer: buffer, bodyStart: bodyStart)
    }
  }

  private struct RequestStart {
    let method: String
    let path: String
  }

  private static func complete(
    start: RequestStart, headerLines: [String], buffer: Data, bodyStart: Data.Index
  ) -> HTTPParseOutcome {
    var headers: [String: String] = [:]
    for line in headerLines where !line.isEmpty {
      guard let separator = line.firstIndex(of: ":") else {
        return .failed(.malformedHeader(line))
      }
      let name = String(line[line.startIndex..<separator])
      let value = String(line[line.index(after: separator)...])
        .trimmingCharacters(in: .whitespaces)
      headers[name] = merged(existing: headers[name], value: value)
    }

    switch bodyLength(headers) {
    case .failure(let failure):
      return .failed(failure)
    case .success(let length):
      let available = buffer.distance(from: bodyStart, to: buffer.endIndex)
      guard available >= length else { return .incomplete }
      let end = buffer.index(bodyStart, offsetBy: length)
      return .complete(
        ParsedHTTPRequest(
          method: start.method,
          path: start.path,
          headers: headers,
          body: Data(buffer[bodyStart..<end]),
          byteCount: buffer.distance(from: buffer.startIndex, to: end)))
    }
  }

  /// A repeated header is joined rather than overwritten, which is what RFC 9110
  /// says a list-valued field means and what keeps two `Accept` lines from
  /// becoming one.
  private static func merged(existing: String?, value: String) -> String {
    guard let existing, !existing.isEmpty else { return value }
    return "\(existing), \(value)"
  }

  private static func start(_ line: String) -> Result<RequestStart, HTTPParseFailure> {
    let parts = line.split(separator: " ", omittingEmptySubsequences: true)
    guard parts.count == 3 else { return .failure(.malformedRequestLine) }
    let version = String(parts[2])
    guard version == "HTTP/1.1" || version == "HTTP/1.0" else {
      return .failure(.unsupportedVersion(version))
    }
    // The query string is dropped: the SDK's validators match on the path, and
    // nothing in this endpoint takes a query parameter.
    let target = String(parts[1])
    let path = target.split(separator: "?", maxSplits: 1).first.map(String.init) ?? "/"
    return .success(RequestStart(method: String(parts[0]).uppercased(), path: path))
  }

  private static func bodyLength(_ headers: [String: String]) -> Result<Int, HTTPParseFailure> {
    let lowercased = headers.reduce(into: [String: String]()) { $0[$1.key.lowercased()] = $1.value }
    let encoding = lowercased["transfer-encoding"]?.lowercased() ?? ""
    guard !encoding.contains("chunked") else { return .failure(.chunkedBodyUnsupported) }
    guard let raw = lowercased["content-length"] else { return .success(0) }
    guard let length = Int(raw.trimmingCharacters(in: .whitespaces)), length >= 0 else {
      return .failure(.invalidContentLength(raw))
    }
    guard length <= HTTPWireFormat.maximumBodyBytes else { return .failure(.bodyTooLarge) }
    return .success(length)
  }

  /// `Data.range(of:)` exists on `Foundation`, but not with the slicing
  /// behaviour this needs on a `Data` whose indices do not start at zero.
  private static func range(of pattern: Data, in buffer: Data) -> Range<Data.Index>? {
    guard buffer.count >= pattern.count, !pattern.isEmpty else { return nil }
    let last = buffer.index(buffer.endIndex, offsetBy: -pattern.count)
    var index = buffer.startIndex
    while index <= last {
      let end = buffer.index(index, offsetBy: pattern.count)
      if buffer[index..<end].elementsEqual(pattern) { return index..<end }
      index = buffer.index(after: index)
    }
    return nil
  }
}
