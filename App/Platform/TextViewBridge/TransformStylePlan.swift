import AppKit
import ItchyCore
import ItchyServices

/// What styling a transform's output is given when it goes back into the pad
/// (D-11, §7.3 step 4).
///
/// A transform returns characters, not attributes, so something has to decide
/// what the replacement looks like. The rule has two cases and both are
/// decisions rather than mechanics, which is why they are here rather than in
/// the coordinator that applies them.
enum TransformStylePlan {
  enum Style: Equatable {
    /// Take the attributes found at the start of the replaced range, so that a
    /// transform applied inside styled text keeps the local style.
    case inheritFromRangeStart
    /// The pad's body font and nothing else.
    case bodyFontOnly
  }

  static func style(forTransform id: String, mode: PadMode) -> Style {
    // A plain pad has no attributes to inherit, and flatten exists precisely to
    // discard the ones a styled pad has (`FR-4.5`).
    guard mode == .styled, id != FlattenTransform().id else { return .bodyFontOnly }
    return .inheritFromRangeStart
  }
}
