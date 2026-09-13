import ItchyCore
import SwiftUI

/// How the pad's formatting controls are drawn (D-11, D-20).
enum FormattingBarModel {
  /// The controls' presence, as a whole.
  enum Visibility: Equatable, Sendable {
    case shown
    /// Collapsed rather than merely transparent, so a plain pad's status bar is
    /// not left with a gap where the buttons would be.
    case collapsed

    var width: CGFloat? {
      switch self {
      case .shown: nil
      case .collapsed: 0
      }
    }

    var opacity: Double {
      switch self {
      case .shown: 1
      case .collapsed: 0
      }
    }

    var isDisabled: Bool { self == .collapsed }
  }

  static func visibility(for mode: PadMode) -> Visibility {
    switch FormattingPlan.availability(for: mode) {
    case .available: .shown
    case .unavailable: .collapsed
    }
  }

  static func symbol(for trait: FormatTrait) -> String {
    trait.rawValue
  }

  static func help(for trait: FormatTrait) -> String {
    switch trait {
    case .bold: "Bold (⌘B)"
    case .italic: "Italic (⌘I)"
    case .underline: "Underline (⌘U)"
    }
  }

  static func style(isActive: Bool) -> AnyShapeStyle {
    isActive ? AnyShapeStyle(.tint) : AnyShapeStyle(.secondary)
  }

  static func accessibilityValue(isActive: Bool) -> String {
    isActive ? "on" : "off"
  }
}
