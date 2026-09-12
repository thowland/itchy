import Foundation

/// The passage of time, injected.
///
/// `SaveScheduler` debounces on 750 milliseconds, and a test that actually waits
/// 750 milliseconds to observe that is a test that will be deleted within a month
/// for being slow. This is the seam that lets the suite assert the scheduler
/// *asked* for the interval, that cancelling before it elapsed prevented the
/// write, and that a forced flush bypassed it — with no real time passing
/// (specification §6.6, implementation plan §14.1).
public protocol Sleeping: Sendable {
  func sleep(for duration: Duration) async throws
}

/// Real time.
public struct SystemSleeper: Sleeping {
  public init() {}

  public func sleep(for duration: Duration) async throws {
    try await Task.sleep(for: duration)
  }
}
