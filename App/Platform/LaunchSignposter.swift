import Foundation
import OSLog

/// Instrumentation for the one number that matters (`NFR-1.1`, §8.7).
///
/// 250 ms at the ninety-fifth percentile, from hotkey press to a focused,
/// typeable pad. The vision document's stated failure mode is friction in the
/// first two seconds of use, so this is measured rather than judged by feel —
/// and the performance suite reads these intervals rather than a stopwatch.
@MainActor
final class LaunchSignposter {
  private let signposter = OSSignposter(
    subsystem: "com.wdogsystems.itchy", category: "launch")

  /// Wall-clock duration of the most recent hotkey-to-pad interval, in seconds.
  ///
  /// Kept alongside the signpost so a test can assert on it without parsing the
  /// unified log.
  private(set) var lastHotKeyDuration: TimeInterval?
  private(set) var lastLaunchDuration: TimeInterval?

  struct Interval {
    let state: OSSignpostIntervalState
    let started: CFAbsoluteTime
  }

  func beginLaunch() -> Interval {
    Interval(
      state: signposter.beginInterval("launch"),
      started: CFAbsoluteTimeGetCurrent())
  }

  func endLaunch(_ interval: Interval) {
    signposter.endInterval("launch", interval.state)
    lastLaunchDuration = CFAbsoluteTimeGetCurrent() - interval.started
  }

  func beginHotKey() -> Interval {
    Interval(
      state: signposter.beginInterval("hotkey-to-visible"),
      started: CFAbsoluteTimeGetCurrent())
  }

  func endHotKey(_ interval: Interval) {
    signposter.endInterval("hotkey-to-visible", interval.state)
    lastHotKeyDuration = CFAbsoluteTimeGetCurrent() - interval.started
  }
}
