import Foundation
import Network

/// One accepted connection, with `NWConnection`'s callbacks turned into `await`.
///
/// Performs only. What the bytes mean is `HTTPRequestParser`'s and what to
/// answer is the SDK's or `MCPAuthorization`'s; this reads, writes and closes.
internal actor LoopbackConnection {
  internal enum ConnectionError: Error, Equatable {
    case closed
    case failed(String)
  }

  /// How much is asked for in one read. A tool call carrying a page of text
  /// arrives in one; anything larger arrives in several, which the parser
  /// already handles.
  internal static let readSize = 64 * 1024

  /// Shorthand so each continuation's type fits on the closure's own line,
  /// which is what the closure-parameter-position rule asks for. The same
  /// device as `Waiter` in the core's test support.
  private typealias VoidWaiter = CheckedContinuation<Void, any Error>
  private typealias DataWaiter = CheckedContinuation<Data?, any Error>

  private let connection: NWConnection
  private let queue: DispatchQueue
  private var isFinished = false

  internal init(connection: NWConnection, queue: DispatchQueue) {
    self.connection = connection
    self.queue = queue
  }

  internal func start() async throws {
    try await withCheckedThrowingContinuation { (continuation: VoidWaiter) in
      let once = ResumeOnce(continuation)
      connection.stateUpdateHandler = { state in
        switch state {
        case .ready:
          once.resume(.success(()))
        case .failed(let error):
          once.resume(.failure(ConnectionError.failed(String(describing: error))))
        case .cancelled:
          once.resume(.failure(ConnectionError.closed))
        default:
          break
        }
      }
      connection.start(queue: queue)
    }
  }

  /// The next bytes to arrive, or nil when the peer has finished sending.
  internal func receive() async throws -> Data? {
    try await withCheckedThrowingContinuation { (continuation: DataWaiter) in
      let once = ResumeOnce(continuation)
      connection.receive(
        minimumIncompleteLength: 1, maximumLength: Self.readSize
      ) { data, _, complete, error in
        once.resume(Self.read(data, isComplete: complete, error: error))
      }
    }
  }

  /// What one completed read means.
  ///
  /// Pulled out of the callback because it is the one place in this file that
  /// decides anything: empty bytes mean end-of-stream when the peer is done and
  /// "ask again" when it is not, and getting that backwards is a connection
  /// that either hangs or truncates.
  internal static func read(
    _ data: Data?, isComplete: Bool, error: NWError?
  ) -> Result<Data?, any Error> {
    if let error {
      return .failure(ConnectionError.failed(String(describing: error)))
    }
    if let data, !data.isEmpty {
      return .success(data)
    }
    return .success(isComplete ? nil : Data())
  }

  internal func send(_ data: Data) async throws {
    guard !data.isEmpty else { return }
    try await withCheckedThrowingContinuation { (continuation: VoidWaiter) in
      let once = ResumeOnce(continuation)
      connection.send(
        content: data,
        completion: .contentProcessed { error in
          guard let error else {
            once.resume(.success(()))
            return
          }
          once.resume(.failure(ConnectionError.failed(String(describing: error))))
        })
    }
  }

  internal func close() {
    guard !isFinished else { return }
    isFinished = true
    connection.stateUpdateHandler = nil
    connection.cancel()
  }
}

/// Resumes a continuation exactly once.
///
/// `NWConnection`'s handlers are not promised to fire once — a state handler
/// sees `.ready` and later `.cancelled`, and resuming twice traps. The same
/// shape as `TerminationFlush`'s guard in the app, for the same reason.
private final class ResumeOnce<T: Sendable>: @unchecked Sendable {
  private let lock = NSLock()
  private var continuation: CheckedContinuation<T, any Error>?

  init(_ continuation: CheckedContinuation<T, any Error>) {
    self.continuation = continuation
  }

  func resume(_ result: sending Result<T, any Error>) {
    lock.lock()
    let pending = continuation
    continuation = nil
    lock.unlock()
    pending?.resume(with: result)
  }
}
