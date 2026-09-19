import Foundation
import ItchyCore
import MCP

/// The running server: a loopback socket, a token, and one MCP session per
/// client (§11.1, §11.2, `FR-8.1`–`FR-8.5`).
///
/// Owns no policy. Whether a request is authorised is `MCPAuthorization`'s,
/// which session it belongs to is `MCPSessionRouter`'s, what a tool call means
/// is `ToolRouter`'s, and which pads exist for the caller is `ExposurePolicy`'s.
/// This holds the objects those decisions are about and does what they say.
///
/// One `Server` and one `StatefulHTTPServerTransport` per session, because the
/// SDK's stateful transport holds exactly one session — and `FR-8.2` asks for
/// the shim and a direct client to be connected at the same time, both seeing
/// the same pad state. They do: the state is the store's, not the session's.
public actor MCPServerHost {
  /// How many sessions may be live at once. A person has a handful of agents,
  /// not a thousand, and an unbounded map keyed by a value the client controls
  /// is the sort of thing that is fine until it is not.
  public static let sessionLimit = 16

  public static let path = "/mcp"

  private let service: MCPService
  private let configuredPort: Int
  private let serverName: String
  private let serverVersion: String

  private var token: MCPToken
  private var listener: LoopbackListener?
  private var sessions: [String: MCPSession] = [:]
  private var boundPort: Int?

  public init(
    service: MCPService,
    token: MCPToken,
    port: Int,
    serverName: String = "Itchy",
    serverVersion: String = "0"
  ) {
    self.service = service
    self.token = token
    self.configuredPort = port
    self.serverName = serverName
    self.serverVersion = serverVersion
  }

  public var port: Int? { boundPort }

  public var sessionCount: Int { sessions.count }

  /// Binds and begins serving, answering with the port actually bound.
  @discardableResult
  public func start() async throws -> Int {
    guard listener == nil else { throw LoopbackListener.ListenerError.couldNotBind("already running") }
    let listener = LoopbackListener(port: configuredPort) { [weak self] request in
      guard let self else {
        return .complete(status: 503, headers: [:], body: nil)
      }
      return await self.answer(request)
    }
    self.listener = listener
    let bound = try await listener.start()
    boundPort = bound
    return bound
  }

  public func stop() async {
    await listener?.stop()
    listener = nil
    boundPort = nil
    let running = sessions.values
    sessions.removeAll()
    for session in running { await session.shutDown() }
  }

  /// Replaces the token in one step (`FR-8.4`).
  ///
  /// Live sessions are torn down as well, because the previous token must stop
  /// working *immediately*, and a session established under it would otherwise
  /// keep working on a session identifier alone.
  public func replaceToken(with token: MCPToken) async {
    self.token = token
    let running = sessions.values
    sessions.removeAll()
    for session in running { await session.shutDown() }
  }

  // MARK: - Request handling

  private func answer(_ request: ParsedHTTPRequest) async -> LoopbackResponse {
    // Refused before the SDK sees anything (§11.2).
    let decision = MCPAuthorization.decide(
      header: request.header("Authorization"), expected: token)
    guard decision == .allowed else {
      return refusal(status: decision.statusCode, message: AuthorizationText.of(decision))
    }

    let route = MCPSessionRouter.route(
      sessionID: request.header(HTTPHeaderName.sessionID),
      isInitialize: MCPBodyInspector.isInitialize(request.body),
      known: Set(sessions.keys))

    switch route {
    case .existing(let id):
      guard let session = sessions[id] else {
        return refusal(status: 404, message: "That session is no longer running.")
      }
      return await deliver(request, to: session, recording: false)
    case .create:
      guard sessions.count < Self.sessionLimit else {
        return refusal(status: 503, message: "Too many agent sessions are open.")
      }
      return await deliver(request, to: await makeSession(), recording: true)
    case .unknown:
      return refusal(status: 404, message: "That session is no longer running.")
    case .missing:
      return refusal(status: 400, message: "An Mcp-Session-Id header is required.")
    }
  }

  private func deliver(
    _ request: ParsedHTTPRequest, to session: MCPSession, recording: Bool
  ) async -> LoopbackResponse {
    let response = await session.handle(
      HTTPRequest(
        method: request.method,
        headers: request.headers,
        body: request.body.isEmpty ? nil : request.body,
        path: request.path))
    if recording, let id = response.headers[HTTPHeaderName.sessionID] {
      sessions[id] = session
    }
    if request.method == "DELETE", let id = request.header(HTTPHeaderName.sessionID) {
      sessions[id] = nil
      await session.shutDown()
    }
    return wire(response)
  }

  private func wire(_ response: HTTPResponse) -> LoopbackResponse {
    switch response {
    case .stream(let events, let headers):
      return .stream(status: response.statusCode, headers: headers, events)
    default:
      return .complete(
        status: response.statusCode, headers: response.headers, body: response.bodyData)
    }
  }

  private func refusal(status: Int, message: String) -> LoopbackResponse {
    .complete(
      status: status,
      headers: [
        "Content-Type": "application/json",
        // `WWW-Authenticate` says what is missing rather than only that
        // something is. A client that has never been configured and one whose
        // token was regenerated both land here, and both need telling.
        HTTPHeaderName.wwwAuthenticate: #"Bearer realm="Itchy""#,
      ],
      body: HTTPResponseWriter.jsonRPCError(code: -32_600, message: message))
  }

  private func makeSession() async -> MCPSession {
    let session = MCPSession(
      service: service, name: serverName, version: serverVersion)
    await session.start()
    return session
  }
}

/// What a refusal says, out of the code path that makes it (D-11).
internal enum AuthorizationText {
  internal static func of(_ decision: AuthorizationDecision) -> String {
    switch decision {
    case .allowed: "Allowed."
    case .missingCredential:
      "This server needs a bearer token. Itchy shows it in Settings, under Agents."
    case .rejected:
      "That token is not this server's. If it was regenerated, copy the new one "
        + "from Settings, under Agents."
    }
  }
}

/// One client's session: an SDK server and the transport it speaks through.
internal actor MCPSession {
  private let service: MCPService
  private let server: Server
  private let transport: StatefulHTTPServerTransport

  internal init(service: MCPService, name: String, version: String) {
    self.service = service
    self.transport = StatefulHTTPServerTransport()
    self.server = Server(
      name: name,
      version: version,
      instructions: MCPSession.instructions,
      capabilities: .init(
        resources: .init(subscribe: false, listChanged: false),
        tools: .init(listChanged: false)))
  }

  internal func start() async {
    await register()
    try? await server.start(transport: transport)
  }

  internal func handle(_ request: HTTPRequest) async -> HTTPResponse {
    await transport.handleRequest(request)
  }

  internal func shutDown() async {
    await server.stop()
  }

  /// Said to the agent once, at initialisation, rather than repeated in every
  /// tool description: these pads are transient, and the person can see what
  /// was written.
  internal static let instructions = """
    Itchy holds a small fixed set of scratchpads. Only pads the person has \
    explicitly exposed are visible here, and pads are for transient working \
    text — nothing filed, nothing permanent. Every write is marked in the \
    interface as having come from an agent.
    """

  private func register() async {
    let service = self.service
    await server.withMethodHandler(ListTools.self) { _ in
      ListTools.Result(tools: MCPToolCodec.tools)
    }
    await server.withMethodHandler(CallTool.self) { parameters in
      await MCPSession.call(parameters, on: service)
    }
    await server.withMethodHandler(ListResources.self) { _ in
      ListResources.Result(resources: await MCPSession.resources(of: service))
    }
    await server.withMethodHandler(ReadResource.self) { parameters in
      try await MCPSession.read(parameters.uri, from: service)
    }
  }

  /// A tool that could not be routed answers with `isError` and a message,
  /// rather than a protocol error. The distinction matters to an agent: a
  /// protocol error is a client bug to give up on, an error result is something
  /// to read and try differently.
  /// Shorthand so the signatures fit on one line, which is what the brace-style
  /// rule and the formatter between them insist on.
  private typealias Call = CallTool.Parameters
  private typealias Read = ReadResource.Result

  private static func call(_ call: Call, on service: MCPService) async -> CallTool.Result {
    do {
      let operation = try ToolRouter.route(
        tool: call.name,
        arguments: MCPArgumentCodec.strings(from: call.arguments),
        visiblePads: await service.visiblePads())
      return CallTool.Result(content: MCPResultCodec.content(for: try await service.execute(operation)))
    } catch {
      return CallTool.Result(
        content: [.text(text: MCPSession.message(for: error), annotations: nil, _meta: nil)],
        isError: true)
    }
  }

  private static func resources(of service: MCPService) async -> [Resource] {
    await service.visiblePads().map { pad in
      Resource(
        name: pad.name,
        uri: MCPToolSurface.resourceURI(for: pad.id),
        description: "An Itchy scratchpad, as plain text.",
        mimeType: "text/plain")
    }
  }

  private static func read(_ uri: String, from service: MCPService) async throws -> Read {
    do {
      let text = try await service.readResource(uri: uri)
      return Read(contents: [.text(text, uri: uri, mimeType: "text/plain")])
    } catch {
      throw MCPError.invalidParams(MCPSession.message(for: error))
    }
  }

  internal static func message(for error: any Error) -> String {
    if let routing = error as? MCPRoutingError { return routing.message }
    if let refusal = error as? MCPWriteRefusal { return refusal.message }
    if let fault = error as? PadStoreFault { return fault.reason }
    return "That could not be done."
  }
}
