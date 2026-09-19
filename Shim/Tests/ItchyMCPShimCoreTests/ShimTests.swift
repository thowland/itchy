import Foundation
import ItchyCore
import Testing

@testable import ItchyMCPShimCore

/// The shim's decisions, none of which need a server or a client.
@Suite("Stdio shim")
struct ShimTests {
  private func endpoint(port: Int = 8_899, pid: Int32 = 42) -> MCPEndpoint {
    MCPEndpoint(port: port, processIdentifier: pid, startedAt: Date())
  }

  // MARK: - Where to connect

  @Test("With a live endpoint and a token, it knows where to go")
  func resolvesReady() {
    let resolution = ShimConfiguration.resolve(
      endpoint: endpoint(), token: "abc", isRunning: { _ in true })
    #expect(resolution == .ready(url: URL(string: "http://127.0.0.1:8899/mcp")!, token: "abc"))
    #expect(ShimConfiguration.message(for: resolution) == nil)
  }

  /// No endpoint file means the server is off. That is the most common reason
  /// this fails and the message has to say what to do about it.
  @Test("No endpoint file reads as a server that is not running")
  func serverOff() {
    let resolution = ShimConfiguration.resolve(
      endpoint: nil, token: "abc", isRunning: { _ in true })
    #expect(resolution == .serverNotRunning)
    #expect(ShimConfiguration.message(for: resolution)?.contains("Settings → Agents") == true)
  }

  /// A file left by a crash. Connecting to the port it names would either fail
  /// obscurely or, worse, reach whatever took the port afterwards.
  @Test("An endpoint file whose process is gone is recognised as stale")
  func staleEndpoint() {
    let resolution = ShimConfiguration.resolve(
      endpoint: endpoint(pid: 999), token: "abc", isRunning: { _ in false })
    #expect(resolution == .staleEndpoint(processIdentifier: 999))
    #expect(ShimConfiguration.message(for: resolution)?.contains("999") == true)
  }

  @Test("A missing or blank token is refused with the variable's name")
  func missingToken() {
    for token in [nil, "", "   "] as [String?] {
      let resolution = ShimConfiguration.resolve(
        endpoint: endpoint(), token: token, isRunning: { _ in true })
      #expect(resolution == .noToken)
      #expect(
        ShimConfiguration.message(for: resolution)?.contains(ShimConfiguration.tokenVariable)
          == true)
    }
  }

  /// The flag exists so FR-8.2's acceptance criterion can be run at all.
  @Test("A support directory can be named on the command line")
  func supportRootFlag() {
    #expect(ShimConfiguration.supportRoot(in: ["--support-root", "/tmp/x"]) == "/tmp/x")
    #expect(ShimConfiguration.supportRoot(in: []) == nil)
    // A flag with nothing after it is not a path.
    #expect(ShimConfiguration.supportRoot(in: ["--support-root"]) == nil)
  }

  // MARK: - Stdio framing

  @Test("One message per line, and the newline is the frame")
  func framesLines() {
    var buffer = Data("{\"a\":1}\n{\"b\":2}\n".utf8)
    let messages = StdioFraming.messages(in: &buffer)
    #expect(messages.map { String(bytes: $0, encoding: .utf8) } == ["{\"a\":1}", "{\"b\":2}"])
    #expect(buffer.isEmpty)
    #expect(StdioFraming.line(Data("x".utf8)) == Data("x\n".utf8))
  }

  /// A message arriving in two reads is one message. Getting this wrong is the
  /// classic stdio bug and it only shows up under load.
  @Test("A message split across reads is not two messages")
  func framesPartialReads() {
    var buffer = Data("{\"a\":".utf8)
    #expect(StdioFraming.messages(in: &buffer).isEmpty)
    buffer.append(Data("1}\n".utf8))
    #expect(
      StdioFraming.messages(in: &buffer).map { String(bytes: $0, encoding: .utf8) }
        == ["{\"a\":1}"])
  }

  @Test("Blank lines and carriage returns are framing, not content")
  func tolerantFraming() {
    var buffer = Data("{\"a\":1}\r\n\n{\"b\":2}\n".utf8)
    #expect(StdioFraming.messages(in: &buffer).count == 2)
  }

  // MARK: - Server-sent events

  /// The server answers a request with an event stream, so this is not
  /// optional — without it the client waits forever for a reply that arrived.
  @Test("The JSON-RPC message is taken out of an event stream")
  func parsesEventStream() {
    let body = Data("event: message\ndata: {\"jsonrpc\":\"2.0\",\"id\":1}\n\n".utf8)
    #expect(
      ServerSentEvents.payloads(in: body).map { String(bytes: $0, encoding: .utf8) }
        == ["{\"jsonrpc\":\"2.0\",\"id\":1}"])
  }

  /// The transport sends one of these for resumability before anything real.
  @Test("A priming event with empty data is not forwarded as a message")
  func ignoresPrimingEvent() {
    let body = Data("id: _GET_stream_1\ndata: \n\nevent: message\ndata: {\"ok\":true}\n\n".utf8)
    #expect(
      ServerSentEvents.payloads(in: body).map { String(bytes: $0, encoding: .utf8) }
        == ["{\"ok\":true}"])
  }

  @Test("Several events in one body are several messages")
  func parsesSeveralEvents() {
    let body = Data("data: {\"a\":1}\n\ndata: {\"b\":2}\n\n".utf8)
    #expect(ServerSentEvents.payloads(in: body).count == 2)
  }

  @Test("Data spread over several lines is one message")
  func joinsMultilineData() {
    let body = Data("data: {\"a\":\ndata: 1}\n\n".utf8)
    #expect(
      String(bytes: ServerSentEvents.payloads(in: body)[0], encoding: .utf8)
        == "{\"a\":\n1}")
  }

  // MARK: - What a response means

  @Test("A notification's 202 produces no reply, so the client does not wait")
  func acceptedIsSilent() {
    #expect(ResponseHandling.decide(status: 202, contentType: nil) == .silent)
  }

  @Test("Content type decides how a 200 is read")
  func contentTypeRouting() {
    #expect(
      ResponseHandling.decide(status: 200, contentType: "text/event-stream")
        == .forwardEventStream)
    #expect(
      ResponseHandling.decide(status: 200, contentType: "application/json; charset=utf-8")
        == .forwardJSON)
    #expect(ResponseHandling.decide(status: 200, contentType: nil) == .silent)
  }

  @Test("A refusal is a failure with its status, not a body to forward")
  func failures() {
    #expect(
      ResponseHandling.decide(status: 401, contentType: "application/json")
        == .failed(status: 401))
    #expect(ResponseHandling.decide(status: 404, contentType: nil) == .failed(status: 404))
  }

  /// The two that will actually happen, and the person reading a client log is
  /// the only one who will see them.
  @Test("The advice for a refused token and a dead session says what to do")
  func advice() {
    #expect(Proxy.advice(for: 401).contains("regenerating it"))
    #expect(Proxy.advice(for: 404).contains("restart"))
    #expect(Proxy.advice(for: 500).isEmpty == false)
  }

  /// Null rather than the request's id, because echoing the right one would
  /// mean parsing the request, and this thing must not parse requests.
  @Test("A transport error is valid JSON-RPC with a null id")
  func transportError() throws {
    let data = Proxy.transportError("gone")
    let json = try #require(try JSONSerialization.jsonObject(with: data) as? [String: Any])
    #expect(json["jsonrpc"] as? String == "2.0")
    #expect(json["id"] is NSNull)
    #expect((json["error"] as? [String: Any])?["message"] as? String == "gone")
  }
}
