import AppKit
import ItchyCore
import SwiftUI

/// What the accent control offers (`FR-3.8`, D-33).
///
/// A case rather than an optional colour, because "no rule", "a palette colour"
/// and "a colour of my own" are three different answers and the control has to
/// show all three at once.
enum PadAccentChoice: Hashable {
  case none
  case named(PadAccentName)
  case custom
}

/// The accent control's rows, labels and consequences (D-11).
///
/// The view builds a picker from `all` and applies what `accent(for:current:)`
/// returns; it decides nothing itself.
enum PadAccentModel {
  static let label = "Accent rule"

  static let customLabel = "Custom…"

  static let noneLabel = "None"

  /// None first, the palette in the middle, custom last — the order somebody
  /// reads them in, and the order of how much the choice commits them to.
  static let all: [PadAccentChoice] =
    [.none] + PadAccentName.allCases.map(PadAccentChoice.named) + [.custom]

  static func choice(for accent: PadAccent?) -> PadAccentChoice {
    switch accent {
    case .none: return .none
    case .named(let name): return .named(name)
    case .custom: return .custom
    }
  }

  /// What the pad's accent becomes when a row is picked.
  ///
  /// Choosing "Custom…" keeps a colour the pad already had rather than
  /// resetting it, so that leaving the picker and coming back does not discard
  /// the colour somebody chose. Arriving at custom from a palette colour seeds
  /// the picker with that colour's light value, which gives the picker
  /// somewhere sensible to open rather than at black.
  static func accent(for choice: PadAccentChoice, current: PadAccent?) -> PadAccent? {
    switch choice {
    case .none:
      return nil
    case .named(let name):
      return .named(name)
    case .custom:
      if case .custom = current { return current }
      let seed = current ?? .named(.slate)
      return .custom(PadAccentPalette.rgb(of: seed, in: .light))
    }
  }

  static func title(_ choice: PadAccentChoice) -> String {
    switch choice {
    case .none: return noneLabel
    case .named(let name): return name.rawValue.capitalized
    case .custom: return customLabel
    }
  }

  /// Said under the control, and only where there is something to say. A
  /// palette colour carries a value for each appearance and a custom one does
  /// not, which is worth knowing before rather than after switching to dark.
  static func note(for accent: PadAccent?) -> String? {
    guard case .custom = accent else { return nil }
    return "A custom colour is drawn as chosen in both light and dark appearance."
  }

  /// Whether the colour well is shown beside the picker.
  static func showsColorWell(for accent: PadAccent?) -> Bool {
    if case .custom = accent { return true }
    return false
  }
}

/// Between `AccentRGB` and the two colour types the interface needs (D-11).
///
/// A conversion rather than a decision, which is why it is a `Codec`: every
/// function here has exactly one right answer for a given input.
enum AccentColorCodec {
  /// The colour to draw, resolved for the appearance the pad is being drawn in.
  ///
  /// Built as a dynamic `NSColor` rather than resolved once, so that a pad left
  /// open while the system switches to dark redraws in the dark value without
  /// anything having to notice the switch.
  static func dynamicColor(for accent: PadAccent) -> Color {
    Color(
      nsColor: NSColor(name: nil) { appearance in
        color(PadAccentPalette.rgb(of: accent, in: PadAccentModel.appearance(of: appearance)))
      })
  }

  static func color(_ rgb: AccentRGB) -> NSColor {
    NSColor(srgbRed: rgb.red, green: rgb.green, blue: rgb.blue, alpha: 1)
  }

  static func swiftUIColor(_ rgb: AccentRGB) -> Color {
    Color(nsColor: color(rgb))
  }

  /// What the colour well hands back. Converted through sRGB because a colour
  /// picked from the wheel can arrive in a colour space whose components mean
  /// something else, and the file stores three numbers with no space attached.
  static func rgb(_ color: Color) -> AccentRGB? {
    guard let converted = NSColor(color).usingColorSpace(.sRGB) else { return nil }
    return AccentRGB(
      red: Double(converted.redComponent),
      green: Double(converted.greenComponent),
      blue: Double(converted.blueComponent))
  }
}

extension PadAccentModel {
  /// Which set of palette values an `NSAppearance` calls for.
  ///
  /// `bestMatch` rather than a name comparison, because the appearance handed
  /// to a dynamic colour can be a vibrant or accessibility variant whose name
  /// is neither `.aqua` nor `.darkAqua`.
  static func appearance(of appearance: NSAppearance) -> PadAccentPalette.Appearance {
    appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua ? .dark : .light
  }
}
