import Foundation
import Testing

@testable import ItchyServices

/// The wire format, by handing it bytes.
///
/// Every case here is one a socket produces eventually and reproduces never: a
/// header block split across two reads, a body arriving after its headers, two
/// requests in one buffer. Testing them as values is the reason the parser is
/// one.
@Suite("HTTP wire format")
struct HTTPWireFormatTests {
  private func bytes(_ text: String) -> Data { Data(text.utf8) }

  private let post = """
    POST /mcp HTTP/1.1\r
    Host: 127.0.0.1:8899\r
    Authorization: Bearer abc\r
    Content-Length: 2\r
    \r
    {}
    """

  @Test("A complete request parses into its parts")
  func complete() {
    guard case .complete(let request) = HTTPRequestParser.parse(bytes(post)) else {
      Issue.record("expected a complete request")
      return
    }
    #expect(request.method == "POST")
    #expect(request.path == "/mcp")
    #expect(request.header("authorization") == "Bearer abc")
    #expect(request.body == bytes("{}"))
    #expect(request.byteCount == bytes(post).count)
  }

  @Test("Header lookup ignores case, because a client chooses its own")
  func caseInsensitiveHeaders() {
    guard case .complete(let request) = HTTPRequestParser.parse(bytes(post)) else {
      Issue.record("expected a complete request")
      return
    }
    #expect(request.header("AUTHORIZATION") == "Bearer abc")
    #expect(request.header("Host") == "127.0.0.1:8899")
    #expect(request.header("X-Absent") == nil)
  }

  @Test("A request split anywhere parses once the rest arrives")
  func splitAnywhere() {
    let all = bytes(post)
    for split in 1..<all.count {
      let outcome = HTTPRequestParser.parse(all.prefix(split))
      #expect(outcome == .incomplete, "byte \(split) should not have completed")
    }
    guard case .complete = HTTPRequestParser.parse(all) else {
      Issue.record("the whole request should parse")
      return
    }
  }

  @Test("Two requests in one buffer leave the second behind")
  func pipelined() {
    var buffer = bytes(post)
    buffer.append(bytes(post))
    guard case .complete(let first) = HTTPRequestParser.parse(buffer) else {
      Issue.record("expected the first request")
      return
    }
    buffer.removeFirst(first.byteCount)
    guard case .complete(let second) = HTTPRequestParser.parse(buffer) else {
      Issue.record("expected the second request")
      return
    }
    #expect(second.method == "POST")
    #expect(second.byteCount == buffer.count)
  }

  @Test("A GET with no body is complete at the blank line")
  func bodylessGet() {
    let get = "GET /mcp HTTP/1.1\r\nHost: 127.0.0.1:8899\r\n\r\n"
    guard case .complete(let request) = HTTPRequestParser.parse(bytes(get)) else {
      Issue.record("expected a complete request")
      return
    }
    #expect(request.method == "GET")
    #expect(request.body.isEmpty)
  }

  @Test("The query string is dropped, because the validators match on the path")
  func queryDropped() {
    let get = "GET /mcp?session=1 HTTP/1.1\r\nHost: h\r\n\r\n"
    guard case .complete(let request) = HTTPRequestParser.parse(bytes(get)) else {
      Issue.record("expected a complete request")
      return
    }
    #expect(request.path == "/mcp")
  }

  @Test("A repeated header is joined rather than overwritten")
  func repeatedHeader() {
    let get = "GET / HTTP/1.1\r\nAccept: application/json\r\nAccept: text/event-stream\r\n\r\n"
    guard case .complete(let request) = HTTPRequestParser.parse(bytes(get)) else {
      Issue.record("expected a complete request")
      return
    }
    #expect(request.header("accept") == "application/json, text/event-stream")
  }

  @Test("The method is upper-cased so the router need not care")
  func methodNormalised() {
    guard case .complete(let request) = HTTPRequestParser.parse(bytes("delete / HTTP/1.1\r\n\r\n"))
    else {
      Issue.record("expected a complete request")
      return
    }
    #expect(request.method == "DELETE")
  }

  @Test("A malformed request line is refused with 400")
  func malformedRequestLine() {
    #expect(
      HTTPRequestParser.parse(bytes("nonsense\r\n\r\n")) == .failed(.malformedRequestLine))
    #expect(HTTPParseFailure.malformedRequestLine.statusCode == 400)
  }

  @Test("HTTP/2 over a cleartext socket is refused rather than misread")
  func unsupportedVersion() {
    let outcome = HTTPRequestParser.parse(bytes("GET / HTTP/2.0\r\n\r\n"))
    #expect(outcome == .failed(.unsupportedVersion("HTTP/2.0")))
    #expect(HTTPParseFailure.unsupportedVersion("x").statusCode == 505)
  }

  @Test("A header line without a colon is refused")
  func malformedHeader() {
    let outcome = HTTPRequestParser.parse(bytes("GET / HTTP/1.1\r\nbroken\r\n\r\n"))
    #expect(outcome == .failed(.malformedHeader("broken")))
  }

  /// Accepting a subset deliberately is better than accepting a superset
  /// accidentally: an MCP client has no reason to send a chunked body, and
  /// half-reading one would be worse than saying so.
  @Test("A chunked body is refused, not half-read")
  func chunkedRefused() {
    let outcome = HTTPRequestParser.parse(
      bytes("POST / HTTP/1.1\r\nTransfer-Encoding: chunked\r\n\r\n"))
    #expect(outcome == .failed(.chunkedBodyUnsupported))
    #expect(HTTPParseFailure.chunkedBodyUnsupported.statusCode == 411)
  }

  @Test("A Content-Length that is not a length is refused")
  func badContentLength() {
    let outcome = HTTPRequestParser.parse(bytes("POST / HTTP/1.1\r\nContent-Length: ten\r\n\r\n"))
    #expect(outcome == .failed(.invalidContentLength("ten")))
  }

  @Test("A body larger than the ceiling is refused before it is read")
  func bodyTooLarge() {
    let length = HTTPWireFormat.maximumBodyBytes + 1
    let outcome = HTTPRequestParser.parse(
      bytes("POST / HTTP/1.1\r\nContent-Length: \(length)\r\n\r\n"))
    #expect(outcome == .failed(.bodyTooLarge))
    #expect(HTTPParseFailure.bodyTooLarge.statusCode == 413)
  }

  @Test("A header block that never ends is refused rather than buffered forever")
  func headersTooLarge() {
    let flood = "GET / HTTP/1.1\r\n" + String(repeating: "X: y\r\n", count: 20_000)
    #expect(HTTPRequestParser.parse(bytes(flood)) == .failed(.headersTooLarge))
    #expect(HTTPParseFailure.headersTooLarge.statusCode == 431)
  }

  @Test("Every failure says what went wrong")
  func failuresExplainThemselves() {
    let all: [HTTPParseFailure] = [
      .malformedRequestLine, .unsupportedVersion("HTTP/9"), .malformedHeader("x"),
      .headersTooLarge, .bodyTooLarge, .chunkedBodyUnsupported, .invalidContentLength("y"),
    ]
    #expect(all.allSatisfy { !$0.reason.isEmpty })
  }

  // MARK: - Responses

  @Test("A response states its length and keeps the connection")
  func responseFraming() {
    let data = HTTPResponseWriter.response(
      status: 200, headers: ["Content-Type": "application/json"], body: Data("{}".utf8))
    let text = String(bytes: data, encoding: .utf8) ?? ""
    #expect(text.hasPrefix("HTTP/1.1 200 OK\r\n"))
    #expect(text.contains("Content-Length: 2\r\n"))
    #expect(text.contains("Connection: keep-alive\r\n"))
    #expect(text.hasSuffix("\r\n\r\n{}"))
  }

  /// A stream's body ends where the connection ends, so stating a length would
  /// be stating the wrong one.
  @Test("A stream head states no length and closes")
  func streamFraming() {
    let text =
      String(
        bytes: HTTPResponseWriter.streamHead(
          status: 200, headers: ["Content-Type": "text/event-stream"]),
        encoding: .utf8) ?? ""
    #expect(text.contains("Content-Type: text/event-stream\r\n"))
    #expect(text.contains("Connection: close\r\n"))
    #expect(!text.contains("Content-Length"))
  }

  @Test("An empty response still states a zero length")
  func emptyBody() {
    let text = String(bytes: HTTPResponseWriter.response(status: 202), encoding: .utf8) ?? ""
    #expect(text.hasPrefix("HTTP/1.1 202 Accepted\r\n"))
    #expect(text.contains("Content-Length: 0\r\n"))
  }

  @Test("A refusal is JSON-RPC, so a client parses it the way it parses the rest")
  func errorBody() throws {
    let body = HTTPResponseWriter.jsonRPCError(code: -32_600, message: "no")
    let json = try #require(try JSONSerialization.jsonObject(with: body) as? [String: Any])
    #expect(json["jsonrpc"] as? String == "2.0")
    let error = try #require(json["error"] as? [String: Any])
    #expect(error["message"] as? String == "no")
  }

  @Test("Statuses this server uses have their reason phrases")
  func reasonPhrases() {
    #expect(HTTPResponseWriter.reason(for: 401) == "Unauthorized")
    #expect(HTTPResponseWriter.reason(for: 404) == "Not Found")
    #expect(HTTPResponseWriter.reason(for: 405) == "Method Not Allowed")
    #expect(HTTPResponseWriter.reason(for: 599) == "Status 599")
  }
}
