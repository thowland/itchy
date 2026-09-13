import AppKit
import ItchyCore

/// The three traits the pad's formatting controls offer (D-20, `FR-4.11`).
enum FormatTrait: String, CaseIterable, Sendable {
  case bold
  case italic
  case underline
}

/// A run of text, reduced to the traits the controls care about.
struct RunFormat: Equatable, Sendable {
  var isBold = false
  var isItalic = false
  var isUnderlined = false

  func has(_ trait: FormatTrait) -> Bool {
    switch trait {
    case .bold: isBold
    case .italic: isItalic
    case .underline: isUnderlined
    }
  }
}

/// Decisions behind bold, italic and underline (D-20).
///
/// `TextFormatter` reads the selection into `RunFormat` values and carries out
/// what this returns; nothing here touches a text view.
enum FormattingPlan {
  enum Change: Equatable, Sendable {
    case apply
    case remove
  }

  enum Availability: Equatable, Sendable {
    case available
    /// A plain pad holds no attributes (`FR-4.4`).
    case unavailable
  }

  /// A trait reads as on only when every run in the selection has it, as in
  /// TextEdit — which is also why toggling a mixed selection applies it.
  static func active(in runs: [RunFormat]) -> Set<FormatTrait> {
    guard !runs.isEmpty else { return [] }
    return Set(FormatTrait.allCases.filter { trait in runs.allSatisfy { $0.has(trait) } })
  }

  static func change(toggling trait: FormatTrait, runs: [RunFormat]) -> Change {
    active(in: runs).contains(trait) ? .remove : .apply
  }

  static func availability(for mode: PadMode) -> Availability {
    switch mode {
    case .styled: .available
    case .plain: .unavailable
    }
  }

  /// ⌘B, ⌘I and ⌘U, and nothing with a further modifier: ⌘⇧U and the like
  /// belong to other things. Caps Lock is ignored, since it is not a chord.
  ///
  /// Needed at all because Itchy is an accessory application with no menu bar,
  /// so there is no Format menu for these to arrive through.
  static func shortcut(
    characters: String?,
    modifiers: NSEvent.ModifierFlags,
    mode: PadMode
  ) -> FormatTrait? {
    let chord = modifiers.intersection([.command, .shift, .option, .control])
    guard availability(for: mode) == .available, chord == .command else { return nil }
    switch characters?.lowercased() {
    case "b": return .bold
    case "i": return .italic
    case "u": return .underline
    default: return nil
    }
  }

  static func actionName(for trait: FormatTrait) -> String {
    switch trait {
    case .bold: "Bold"
    case .italic: "Italic"
    case .underline: "Underline"
    }
  }
}

/// Whether `updateNSView` needs to reconfigure the text view.
///
/// SwiftUI calls `updateNSView` whenever anything the panel observes changes,
/// which includes every refresh of the pad list. Reconfiguring each time reset
/// the typing attributes, so ⌘B with nothing selected lasted until the next save.
enum ModeConfigurationPlan {
  enum Decision: Equatable, Sendable {
    case reconfigure
    case unchanged
  }

  static func decide(configured: PadMode?, requested: PadMode) -> Decision {
    configured == requested ? .unchanged : .reconfigure
  }
}
