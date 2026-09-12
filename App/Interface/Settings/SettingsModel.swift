import Foundation
import ItchyCore

/// Validation and clamping for the settings window (D-11, specification §15.2).
///
/// The control must not be the only thing stopping an out-of-range value —
/// `FR-2.1` requires the ceiling at three enforcement points, and this is one of
/// them. The others are `SettingsStore.load` and `PadStore.createPad`.
enum SettingsModel {
  /// The range the pad-count control offers.
  static var padCountRange: ClosedRange<Int> {
    PadBounds.minimumCount...PadBounds.hardCeiling
  }

  static func clampPadCount(_ requested: Int) -> Int {
    PadBounds.clamp(requested)
  }

  /// What the pad-count control says about itself.
  ///
  /// The ceiling is stated rather than merely enforced, because a control that
  /// silently refuses is a control the user argues with.
  static var padCountCaption: String {
    "Between \(PadBounds.minimumCount) and \(PadBounds.hardCeiling) pads."
  }

  /// `FR-2.2`: lowering the count below the number of pads that exist deletes
  /// nothing and hides nothing. The setting says so where it is presented.
  static func loweringNotice(padCount: Int, existing: Int) -> String? {
    guard padCount < existing else { return nil }
    return "\(existing) pads already exist. Lowering this affects new pads only; "
      + "nothing is deleted or hidden."
  }

  static func defaultModeLabel(_ mode: PadMode) -> String {
    switch mode {
    case .styled: "Styled — keeps formatting and images"
    case .plain: "Plain — text only"
    }
  }
}
