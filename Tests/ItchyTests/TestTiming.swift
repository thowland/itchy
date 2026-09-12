import Foundation
import Testing

/// Timing rules for the suite.
///
/// We run locally against a store of at most twenty small files. Nothing here
/// legitimately takes ten seconds, so a test that does has not found a slow
/// path — it has hung, and a hung test is a failed test. Waiting helpers
/// therefore fail loudly at the boundary rather than returning quietly and
/// letting the assertion that follows report something misleading.
enum TestTiming {
  /// The ceiling for any single test.
  static let perTest: Duration = .seconds(10)

  /// The ceiling for waiting on one asynchronous condition inside a test.
  static let perCondition: Duration = .seconds(3)

  /// How often a condition is re-checked.
  static let pollInterval: Duration = .milliseconds(5)
}

/// Waits for a condition, and fails the test if it does not come true.
///
/// The previous version of this returned silently on timeout, which meant a
/// hang presented as whichever assertion happened to run next. Reporting the
/// timeout here names the actual problem.
@MainActor
func expect(
  _ description: String,
  within limit: Duration = TestTiming.perCondition,
  toBecomeTrue condition: @MainActor () -> Bool,
  sourceLocation: SourceLocation = #_sourceLocation
) async {
  let deadline = ContinuousClock.now.advanced(by: limit)
  while ContinuousClock.now < deadline {
    if condition() { return }
    try? await Task.sleep(for: TestTiming.pollInterval)
  }
  Issue.record(
    "timed out after \(limit) waiting for: \(description)",
    sourceLocation: sourceLocation)
}
