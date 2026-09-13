import Foundation
import ItchyCore

/// Which text in a pad follows the editor font setting (D-19, `FR-4.10`).
///
/// Styled content carries a concrete font in every run, so a setting cannot
/// reach existing text merely by being the default; it has to be applied, and
/// the question is to which runs. Text in the editor's own font, current or
/// former, is body text and follows the setting. Text that arrived in a font of
/// its own, such as a paste from a web page, keeps it.
enum EditorFontPolicy {
  enum RunTreatment: Equatable, Sendable {
    /// Takes the setting's family and size, keeping bold and italic.
    case followSettingKeepingTraits
    /// Takes the setting's family and size and nothing else, because a plain
    /// pad holds no attributes (`FR-4.4`).
    case followSettingUnstyled
    /// Left exactly as it is.
    case keepOwnFont
  }

  /// The family `NSFont.monospacedSystemFont` reports. It was the only editor
  /// font before this setting existed, so every pad written until then is set
  /// in it, and it is body text permanently.
  static let builtInFamily = ".AppleSystemUIFontMonospaced"

  /// A run with no font at all is body text: it is what a text view gives text
  /// nobody styled.
  static func treatment(
    runFamily: String?,
    mode: PadMode,
    bodyFamilies: Set<String>
  ) -> RunTreatment {
    switch (mode, runFamily) {
    case (.plain, _):
      .followSettingUnstyled
    case (.styled, nil):
      .followSettingKeepingTraits
    case (.styled, .some(let family)):
      bodyFamilies.contains(family) ? .followSettingKeepingTraits : .keepOwnFont
    }
  }

  /// Every family that counts as the editor's own under these settings.
  static func bodyFamilies(for settings: AppSettings) -> Set<String> {
    var families: Set<String> = [builtInFamily]
    families.formUnion(settings.formerEditorFontFamilies)
    settings.editorFontFamily.map { families.insert($0) }
    return families
  }

  /// Settings after a font is chosen.
  ///
  /// The family being replaced is remembered, most recent first, because a pad
  /// that was closed while it was current is restyled only when it is next
  /// opened, and by then its body text is in a family the setting no longer
  /// names. `nil` is the built-in font, which needs no remembering.
  static func choosing(family: String?, size: Double, in settings: AppSettings) -> AppSettings {
    var result = settings
    let replaced = settings.editorFontFamily
    var former = settings.formerEditorFontFamilies.filter { $0 != family }
    if let replaced, replaced != family {
      former.removeAll { $0 == replaced }
      former.insert(replaced, at: 0)
    }
    result.formerEditorFontFamilies = Array(former.prefix(EditorFontBounds.formerFamilyLimit))
    result.editorFontFamily = family
    result.editorFontSize = EditorFontBounds.clamp(size)
    return result
  }
}
