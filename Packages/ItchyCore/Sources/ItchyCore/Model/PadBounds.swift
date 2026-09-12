import Foundation

/// The bound on how many pads may exist (`FR-2.1`).
///
/// The default is configurable and the ceiling is not. The vision document warns
/// that a soft limit tends to erode, so the configurable range is narrow and the
/// ceiling is itself a requirement: twenty pads still fit in one glance at a
/// menu, and a ceiling that cannot be raised from settings, from a defaults
/// write, or from a hand-edited index file is not a limit that erodes quietly.
///
/// Enforced at three points, all three required by `FR-2.1`'s acceptance
/// criterion: the settings control, the read path for a stored preference, and
/// pad creation.
public enum PadBounds {
  public static let minimumCount = 1
  public static let defaultCount = 9
  public static let hardCeiling = 20

  /// Clamps a requested count into the permitted range.
  ///
  /// Used by the settings control and, critically, by the read path — a stored
  /// value above the ceiling is clamped and written back, because `FR-2.1`
  /// specifically includes a hand-edited stored value.
  public static func clamp(_ requested: Int) -> Int {
    min(max(requested, minimumCount), hardCeiling)
  }

  /// Whether a stored preference needs rewriting because it was out of range.
  public static func needsRewrite(_ stored: Int) -> Bool {
    clamp(stored) != stored
  }
}
