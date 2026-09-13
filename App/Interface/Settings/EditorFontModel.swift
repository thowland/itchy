import Foundation
import ItchyCore

/// What the editor font controls offer and say (D-11, D-19).
enum EditorFontModel {
  /// How the built-in font is named in the picker, where it is the `nil` choice.
  static let builtInLabel = "System Monospaced"

  /// Installed families in the order a person looks for them.
  ///
  /// Families whose names begin with a dot are system-private and not meant to
  /// be chosen by name. A stored family that is no longer installed is still
  /// listed, so the picker shows what the setting says rather than going blank;
  /// the editor falls back to the built-in font meanwhile (`BodyFont`).
  static func familyChoices(available: [String], current: String?) -> [String] {
    var families = available.filter { !$0.hasPrefix(".") }
    if let current, !families.contains(current) {
      families.append(current)
    }
    return families.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
  }

  static var sizeRange: ClosedRange<Double> {
    EditorFontBounds.minimumSize...EditorFontBounds.maximumSize
  }

  static func sizeLabel(_ size: Double) -> String {
    "Size: \(Int(size)) pt"
  }

  /// Prose and a fragment of code, since a pad holds both.
  static let sample = "The quick brown fox — {\"id\": 42, \"ok\": true}"

  static let caption =
    "Applies to every pad, including what is already in them. Text pasted in a "
    + "font of its own keeps that font."
}
