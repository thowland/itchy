import Foundation
import ItchyCore
import Network

/// What a request is to be answered with.
///
/// The streaming case is the one that matters: `HTTPResponse.stream` is the
/// server-to-client SSE channel, which means holding the connection open,
/// writing each `Data` as it arrives, and closing cleanly when the stream
/// finishes or the client disconnects.
public enum LoopbackResponse: Sendable {
  case complete(status: Int, headers: [String: String], body: Data?)
  case stream(status: Int, headers: [String: String], AsyncThrowingStream<Data, any Error>)
}

/// Binds `127.0.0.1` and serves HTTP/1.1 (`FR-8.3`, §11.1).
///
/// Loopback is required rather than conventional: the local endpoint is pinned
/// to `127.0.0.1`, so the socket is not reachable on any other address this
/// machine has, and a connection to the same port on the machine's LAN address
/// is refused by the network stack rather than by a check someone has to
/// remember to write.
///
/// The listener performs; it decides nothing. What the bytes mean is
/// `HTTPRequestParser`'s, what to answer is the handler's, and how the answer is
/// framed is `HTTPResponseWriter`'s.
public actor LoopbackListener {
  public enum ListenerError: Error, Equatable {
    case couldNotBind(String)
    case invalidPort(Int)
    case notRunning
  }

  public typealias Handler = @Sendable (ParsedHTTPRequest) async -> LoopbackResponse

  private let requestedPort: Int
  private let handler: Handler
  private let queue = DispatchQueue(label: "com.itchy.mcp.listener")
  private var listener: NWListener?
  private var boundPort: Int?
  private var connections: [UUID: Task<Void, Never>] = [:]

  public init(port: Int, handler: @escaping Handler) {
    self.requestedPort = port
    self.handler = handler
  }

  public var port: Int? { boundPort }

  /// Binds, and answers with the port actually bound — which is not necessarily
  /// the one asked for, and is what `endpoint.json` records.
  @discardableResult
  public func start() async throws -> Int {
    guard let port = NWEndpoint.Port(rawValue: UInt16(exactly: requestedPort) ?? 0),
      requestedPort >= 0, requestedPort <= Int(UInt16.max)
    else {
      throw ListenerError.invalidPort(requestedPort)
    }
    let parameters = NWParameters.tcp
    parameters.allowLocalEndpointReuse = true
    // `FR-8.3`. Never `0.0.0.0`: pinning the local endpoint is what makes the
    // socket unreachable from another machine, rather than a check in a handler.
    parameters.requiredLocalEndpoint = NWEndpoint.hostPort(
      host: NWEndpoint.Host(MCPEndpoint.loopbackHost), port: port)

    let listener: NWListener
    do {
      listener = try NWListener(using: parameters)
    } catch {
      throw ListenerError.couldNotBind(String(describing: error))
    }
    self.listener = listener
    listener.newConnectionHandler = { [weak self] connection in
      guard let self else {
        connection.cancel()
        return
      }
      Task { await self.accept(connection) }
    }
    let bound = try await waitUntilReady(listener)
    boundPort = bound
    return bound
  }

  /// Stops, and does not return until the socket is actually closed.
  ///
  /// `NWListener.cancel()` is a request, not an event: it returns while the
  /// socket is still accepting, so a disable followed immediately by a check
  /// finds the port still answering. `FR-8.10` says disabling takes effect
  /// without a relaunch, and "takes effect" has to mean by the time this
  /// returns, or the setting and the world disagree for an interval nobody can
  /// predict.
  public func stop() async {
    guard let listener else { return }
    self.listener = nil
    boundPort = nil
    let running = connections.values
    connections.removeAll()
    for task in running { task.cancel() }

    listener.newConnectionHandler = nil
    await withCheckedContinuation { continuation in
      let once = ListenerStopOnce(continuation)
      listener.stateUpdateHandler = { state in
        if case .cancelled = state { once.resume() }
      }
      listener.cancel()
    }
  }

  private func waitUntilReady(_ listener: NWListener) async throws -> Int {
    try await withCheckedThrowingContinuation { continuation in
      let once = ListenerResumeOnce(continuation)
      listener.stateUpdateHandler = { state in
        switch state {
        case .ready:
          once.resume(.success(Int(listener.port?.rawValue ?? 0)))
        case .failed(let error), .waiting(let error):
          // `.waiting` is normally transient, but for a listener it means the
          // port is taken — and waiting forever for a port another process holds
          // presents as a hang rather than as the error it is.
          once.resume(.failure(ListenerError.couldNotBind(String(describing: error))))
        case .cancelled:
          once.resume(.failure(ListenerError.notRunning))
        default:
          break
        }
      }
      listener.start(queue: queue)
    }
  }

  private func accept(_ connection: NWConnection) {
    let id = UUID()
    let handler = self.handler
    let queue = self.queue
    connections[id] = Task { [weak self] in
      let session = LoopbackConnection(connection: connection, queue: queue)
      await LoopbackExchange.serve(session, handler: handler)
      await self?.forget(id)
    }
  }

  private func forget(_ id: UUID) {
    connections[id] = nil
  }
}

/// Reads requests off one connection and writes the answers back.
///
/// Separated from the listener so that the request/response loop is one thing
/// rather than a method on an actor that also owns a socket.
internal enum LoopbackExchange {
  internal static func serve(_ connection: LoopbackConnection, handler: LoopbackListener.Handler) async {
    defer { Task { await connection.close() } }
    do {
      try await connection.start()
      try await pump(connection, handler: handler)
    } catch {
      // A client that goes away mid-request is ordinary, not exceptional: the
      // connection is closed and nothing is reported, because there is nobody
      // left to report it to.
    }
  }

  private static func pump(_ connection: LoopbackConnection, handler: LoopbackListener.Handler) async throws {
    var buffer = Data()
    while !Task.isCancelled {
      switch HTTPRequestParser.parse(buffer) {
      case .failed(let failure):
        try await connection.send(
          HTTPResponseWriter.response(
            status: failure.statusCode,
            headers: ["Content-Type": "application/json"],
            body: HTTPResponseWriter.jsonRPCError(code: -32_600, message: failure.reason),
            continuation: .close))
        return
      case .complete(let request):
        buffer.removeFirst(request.byteCount)
        let keepGoing = try await answer(request, on: connection, handler: handler)
        guard keepGoing else { return }
      case .incomplete:
        guard let more = try await connection.receive() else { return }
        buffer.append(more)
      }
    }
  }

  /// Answers one request, and says whether the connection may carry another.
  private static func answer(
    _ request: ParsedHTTPRequest, on connection: LoopbackConnection,
    handler: LoopbackListener.Handler
  ) async throws -> Bool {
    switch await handler(request) {
    case .complete(let status, let headers, let body):
      try await connection.send(
        HTTPResponseWriter.response(
          status: status, headers: headers, body: body, continuation: .keepAlive))
      return true
    case .stream(let status, let headers, let events):
      try await connection.send(HTTPResponseWriter.streamHead(status: status, headers: headers))
      for try await event in events {
        try await connection.send(event)
      }
      // A stream's body ends where the connection ends, so the connection
      // cannot be reused for a second request.
      return false
    }
  }
}

/// Resumes once when the listener reports itself cancelled.
private final class ListenerStopOnce: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Void, Never>?

  internal init(_ continuation: CheckedContinuation<Void, Never>) {
    self.continuation = continuation
  }

  internal func resume() {
    lock.lock()
    let pending = continuation
    continuation = nil
    lock.unlock()
    pending?.resume()
  }
}

private final class ListenerResumeOnce: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<Int, any Error>?

  internal init(_ continuation: CheckedContinuation<Int, any Error>) {
    self.continuation = continuation
  }

  internal func resume(_ result: Result<Int, any Error>) {
    lock.lock()
    let pending = continuation
    continuation = nil
    lock.unlock()
    pending?.resume(with: result)
  }
}
