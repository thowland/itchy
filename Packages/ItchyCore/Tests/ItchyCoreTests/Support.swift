import Foundation
import Testing

@testable import ItchyCore

/// A temporary directory that removes itself.
struct TemporaryRoot: ~Copyable {
  let url: URL

  init() {
    url = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-tests-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
  }

  var layout: PadStorageLayout {
    PadStorageLayout(root: url)
  }

  deinit {
    try? FileManager.default.removeItem(at: url)
  }
}

/// Time under the test's control.
struct FixedClock: Sendable {
  let instant: Date
  init(_ iso: String = "2026-09-12T12:00:00Z") {
    instant = (try? Date(iso, strategy: JSONCoding.dateStyle)) ?? Date(timeIntervalSince1970: 0)
  }
  var now: @Sendable () -> Date {
    let captured = instant
    return { captured }
  }
}

/// Lets a test decide when a scheduled sleep returns.
///
/// The scheduler debounces on 750 ms and a test that waits 750 ms to observe it
/// is a test that gets deleted for being slow. This records what was asked for
/// and releases it on command, so the suite can assert the interval, assert that
/// cancelling before it elapsed prevented the write, and never wait at all.
/// Shorthand so the continuation's type can be stated on the closure's own line.
typealias Waiter = CheckedContinuation<Void, any Error>

actor ControlledSleeper: Sleeping {
  private var requested: [Duration] = []
  private var waiters: [UUID: CheckedContinuation<Void, any Error>] = [:]
  private var arrivals: [CheckedContinuation<Void, Never>] = []
  private var releasesEverything = false

  /// Responds to cancellation the way `Task.sleep` does, by throwing.
  ///
  /// A double that ignores cancellation leaves an orphaned continuation behind
  /// every cancelled debounce, and the next `advance()` resumes the dead one
  /// instead of the live one. That presents as a hang rather than a failure, so
  /// the fidelity matters.
  func sleep(for duration: Duration) async throws {
    requested.append(duration)
    notifyArrivals()
    guard !releasesEverything else { return }

    let ticket = UUID()
    try await withTaskCancellationHandler {
      try await withCheckedThrowingContinuation { (continuation: Waiter) in
        if Task.isCancelled {
          continuation.resume(throwing: CancellationError())
        } else {
          waiters[ticket] = continuation
        }
      }
    } onCancel: {
      Task { await self.abandon(ticket) }
    }
  }

  /// Suspends until at least `count` sleeps are outstanding.
  ///
  /// Continuation-based rather than a `Task.yield()` spin: several tests waiting
  /// at once on a yield loop starve the cooperative thread pool, which presents
  /// as the whole suite hanging rather than as a failure.
  func waitUntilSleeping(count: Int = 1) async {
    while waiters.count < count {
      await withCheckedContinuation { continuation in
        arrivals.append(continuation)
      }
    }
  }

  var requestedIntervals: [Duration] { requested }

  /// Releases every pending sleep, as if the interval had elapsed.
  func advance() {
    let pending = waiters
    waiters.removeAll()
    for continuation in pending.values {
      continuation.resume()
    }
  }

  /// Releases everything pending and lets any later sleep return immediately.
  ///
  /// Removes the ordering race in tests that re-stage: whether the replacement
  /// task has reached its sleep yet stops mattering.
  func releaseAll() {
    releasesEverything = true
    advance()
  }

  /// Fails every pending sleep, as a cancellation would.
  func interrupt() {
    let pending = waiters
    waiters.removeAll()
    for continuation in pending.values {
      continuation.resume(throwing: CancellationError())
    }
  }

  var waiterCount: Int { waiters.count }

  private func abandon(_ ticket: UUID) {
    guard let continuation = waiters.removeValue(forKey: ticket) else { return }
    continuation.resume(throwing: CancellationError())
  }

  private func notifyArrivals() {
    let pending = arrivals
    arrivals.removeAll()
    for continuation in pending {
      continuation.resume()
    }
  }
}

/// A filesystem that fails on demand, decorating the real one.
///
/// Tests exercise real filesystem semantics rather than a reimplementation of
/// them; only the failure is synthetic (specification §6.3, `FR-5.6`).
final class FaultInjectingFileSystem: FileSystemOperations, @unchecked Sendable {
  enum Operation: Sendable, Equatable {
    case read
    case write
    case replace
    case diskFull
  }

  struct Failure: Sendable, Equatable {
    let operation: Operation
    let pathSuffix: String
  }

  private let inner = LocalFileSystem()
  private let lock = NSLock()
  private var failures: [Failure] = []
  private var observedWrites: [String] = []

  func arm(_ operation: Operation, on pathSuffix: String) {
    lock.withLock { failures.append(Failure(operation: operation, pathSuffix: pathSuffix)) }
  }

  func disarm() {
    lock.withLock { failures.removeAll() }
  }

  var writes: [String] {
    lock.withLock { observedWrites }
  }

  private func isArmed(_ operation: Operation, for url: URL) -> Bool {
    lock.withLock {
      failures.contains { failure in
        guard failure.operation == operation else { return false }
        return url.path.hasSuffix(failure.pathSuffix)
          || url.lastPathComponent.contains(failure.pathSuffix)
      }
    }
  }

  func fileExists(at url: URL) -> Bool { inner.fileExists(at: url) }
  func isDirectory(at url: URL) -> Bool { inner.isDirectory(at: url) }

  func contents(of url: URL) throws -> Data {
    guard !isArmed(.read, for: url) else { throw CocoaError(.fileReadCorruptFile) }
    return try inner.contents(of: url)
  }

  func write(_ data: Data, to url: URL) throws {
    lock.withLock { observedWrites.append(url.lastPathComponent) }
    guard !isArmed(.diskFull, for: url) else {
      throw NSError(domain: NSCocoaErrorDomain, code: NSFileWriteOutOfSpaceError)
    }
    guard !isArmed(.write, for: url) else { throw CocoaError(.fileWriteUnknown) }
    try inner.write(data, to: url)
  }

  func createDirectory(at url: URL) throws { try inner.createDirectory(at: url) }
  func removeItem(at url: URL) throws { try inner.removeItem(at: url) }

  func replaceItem(at destination: URL, with replacement: URL) throws {
    guard !isArmed(.replace, for: destination) else { throw CocoaError(.fileWriteUnknown) }
    try inner.replaceItem(at: destination, with: replacement)
  }

  func contentsOfDirectory(at url: URL) throws -> [URL] {
    try inner.contentsOfDirectory(at: url)
  }

  func modificationDate(of url: URL) throws -> Date { try inner.modificationDate(of: url) }
  func sizeOfItem(at url: URL) throws -> Int { try inner.sizeOfItem(at: url) }
}
