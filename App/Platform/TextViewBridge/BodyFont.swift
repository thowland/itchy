import AppKit
import ItchyCore

/// Builds the editor font from settings, and sets text in it (D-19).
///
/// Which runs are touched is `EditorFontPolicy`'s decision; this carries it out.
enum BodyFont {
  static func font(for settings: AppSettings) -> NSFont {
    font(family: settings.editorFontFamily, size: settings.editorFontSize)
  }

  /// A family that is no longer installed falls back to the built-in font.
  /// AppKit's own substitute is Helvetica at twelve points, which would read as
  /// the setting being ignored and the size going down rather than up.
  static func font(family: String?, size: Double) -> NSFont {
    let points = CGFloat(EditorFontBounds.clamp(size))
    let builtIn = NSFont.monospacedSystemFont(ofSize: points, weight: .regular)
    guard let family else { return builtIn }
    return NSFontManager.shared.font(withFamily: family, traits: [], weight: 5, size: points)
      ?? builtIn
  }

  /// The families the settings picker offers.
  static var installedFamilies: [String] {
    NSFontManager.shared.availableFontFamilies
  }

  /// Sets body text in `font`, in place.
  ///
  /// Attribute changes only, so a text view's undo stack and the character
  /// ranges it holds are unaffected, and no change notification is sent.
  static func restyle(
    _ text: NSMutableAttributedString,
    to font: NSFont,
    mode: PadMode,
    bodyFamilies: Set<String>
  ) {
    var changes: [(range: NSRange, font: NSFont)] = []
    let whole = NSRange(location: 0, length: text.length)
    text.enumerateAttribute(.font, in: whole) { value, range, _ in
      let existing = value as? NSFont
      let treatment = EditorFontPolicy.treatment(
        runFamily: existing?.familyName, mode: mode, bodyFamilies: bodyFamilies)
      let replacement = self.replacement(for: existing, treatment: treatment, font: font)
      guard let replacement, replacement != existing else { return }
      changes.append((range, replacement))
    }
    guard !changes.isEmpty else { return }
    text.beginEditing()
    for change in changes {
      text.addAttribute(.font, value: change.font, range: change.range)
    }
    text.endEditing()
  }

  private static func replacement(
    for existing: NSFont?,
    treatment: EditorFontPolicy.RunTreatment,
    font: NSFont
  ) -> NSFont? {
    switch treatment {
    case .keepOwnFont: nil
    case .followSettingUnstyled: font
    case .followSettingKeepingTraits: carryingTraits(of: existing, onto: font)
    }
  }

  private static func carryingTraits(of existing: NSFont?, onto font: NSFont) -> NSFont {
    let manager = NSFontManager.shared
    let traits = existing.map { manager.traits(of: $0) } ?? []
    return [NSFontTraitMask.boldFontMask, .italicFontMask]
      .filter { traits.contains($0) }
      .reduce(font) { manager.convert($0, toHaveTrait: $1) }
  }
}
