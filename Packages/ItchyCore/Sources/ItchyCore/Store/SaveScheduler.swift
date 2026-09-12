import Foundation

/// Debounces writes (specification §6.6, `FR-5.5`).
///
/// Staging a pad cancels its pending task and starts a new one that sleeps for
/// the debounce interval and then flushes. Cancellation is checked after the
/// sleep, so a cancelled debounce never writes.
public actor SaveScheduler {
  /// Roughly 750 milliseconds of typing inactivity (`FR-5.5`).
  public static let debounce: Duration = .milliseconds(750)

  private let interval: Duration
  private let sleeper: any Sleeping
  private var pending: [PadID: Task<Void, Never>] = [:]

  public init(interval: Duration = SaveScheduler.debounce, sleeper: any Sleeping = SystemSleeper()) {
    self.interval = interval
    self.sleeper = sleeper
  }

  /// Schedules `flush` to run once the interval elapses without further staging.
  public func schedule(_ id: PadID, flush: @escaping @Sendable () async -> Void) {
    pending[id]?.cancel()
    let interval = interval
    let sleeper = sleeper
    pending[id] = Task { [weak self] in
      do {
        try await sleeper.sleep(for: interval)
      } catch {
        return
      }
      guard !Task.isCancelled else { return }
      await self?.clear(id)
      await flush()
    }
  }

  /// Cancels any pending write for a pad without performing it.
  public func cancel(_ id: PadID) {
    pending[id]?.cancel()
    pending[id] = nil
  }

  public func cancelAll() {
    for task in pending.values {
      task.cancel()
    }
    pending.removeAll()
  }

  /// Whether a write is currently pending for this pad.
  public func isPending(_ id: PadID) -> Bool {
    pending[id] != nil
  }

  public var pendingCount: Int {
    pending.count
  }

  private func clear(_ id: PadID) {
    pending[id] = nil
  }
}
