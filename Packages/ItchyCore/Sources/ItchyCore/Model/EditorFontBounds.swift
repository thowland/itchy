import Foundation

/// The permitted editor text sizes, and how much font history is kept (D-19).
public enum EditorFontBounds {
  public static let minimumSize = 9.0

  /// `NSFont.systemFontSize`, which is what the editor used before the size was a
  /// setting. Written as a number because the core cannot ask AppKit (D-2).
  public static let defaultSize = 13.0

  /// Large enough for someone who needs it, small enough that a pad still shows
  /// a useful amount of text.
  public static let maximumSize = 36.0

  /// How many previously chosen families are remembered so that body text set
  /// in them is still recognised as body text (D-19). Bounded, because every
  /// remembered family is one more font a paste could arrive in and be mistaken
  /// for the editor's own.
  public static let formerFamilyLimit = 8

  /// Whole points only, inside the range. A non-finite value from a hand-edited
  /// file takes the default rather than the nearest bound.
  public static func clamp(_ requested: Double) -> Double {
    guard requested.isFinite else { return defaultSize }
    return min(max(requested.rounded(), minimumSize), maximumSize)
  }
}
