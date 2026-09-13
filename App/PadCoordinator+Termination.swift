import AppKit
import ItchyCore

/// Saving and archiving at quit (`FR-5.5`, D-18).
///
/// Runs from `applicationShouldTerminate` with `.terminateLater`, so the main
/// thread stays free. The earlier version blocked the main thread on a
/// semaphore while a detached task saved, but saving an open pad's editor needs
/// the main actor — so the task could not run until the wait timed out, the
/// application exited, and the last edit and the store's flush were lost.
extension PadCoordinator {
  /// How long quitting may wait for saves before giving up on them.
  static let terminationFlushLimit: Duration = .seconds(2)

  /// Saves every editor and the store, then archives if the save finished.
  ///
  /// The archive comes after the save so that it holds what the user last
  /// typed, and is skipped if the save did not finish, since copying a store
  /// that is still being written could capture a pad half-saved. The next
  /// launch archives it instead.
  func prepareForTermination(limit: Duration = terminationFlushLimit) async {
    let outcome = await TerminationFlush.run(limit: limit) { [weak self] in
      await self?.flushEverything()
    }
    switch ArchivePolicy.quitArchive(after: outcome) {
    case .take: archiveIfNeeded(trigger: .quit)
    case .skip: break
    }
  }
}

/// Runs an operation against a deadline, reporting which came first.
///
/// The operation is not cancelled when the deadline wins; the application is
/// about to exit, and interrupting a write part-way is worse than abandoning it.
@MainActor
enum TerminationFlush {
  static func run(
    limit: Duration,
    operation: @escaping @MainActor () async -> Void
  ) async -> FlushOutcome {
    await withCheckedContinuation { continuation in
      let once = ResumeOnce(continuation)
      Task { @MainActor in
        await operation()
        once.resume(with: .completed)
      }
      Task { @MainActor in
        try? await Task.sleep(for: limit)
        once.resume(with: .timedOut)
      }
    }
  }
}

/// Resumes a continuation exactly once, whichever task gets there first.
@MainActor
private final class ResumeOnce {
  private var continuation: CheckedContinuation<FlushOutcome, Never>?

  init(_ continuation: CheckedContinuation<FlushOutcome, Never>) {
    self.continuation = continuation
  }

  func resume(with outcome: FlushOutcome) {
    continuation?.resume(returning: outcome)
    continuation = nil
  }
}
