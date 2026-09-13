import AppKit
import ItchyCore

/// The editor font setting (D-19, `FR-4.10`).
extension PadCoordinator {
  var editorFont: NSFont { BodyFont.font(for: settings) }

  /// Persists the choice and restyles every open pad in place.
  ///
  /// Neither undoable nor staged: it changes how text is set rather than what a
  /// pad says, and content read from the store is restyled on its way into a
  /// panel regardless. The next save of each pad carries the new fonts with it.
  func setEditorFont(family: String?, size: Double) {
    settings = EditorFontPolicy.choosing(family: family, size: size, in: settings)
    persistSettings()
    let font = editorFont
    let families = EditorFontPolicy.bodyFamilies(for: settings)
    for editor in editors.values {
      editor.applyBodyFont(font, bodyFamilies: families)
    }
  }

  /// Content on its way into a panel, set in the current editor font.
  func restyledForDisplay(_ content: NSAttributedString, mode: PadMode) -> NSAttributedString {
    let restyled = NSMutableAttributedString(attributedString: content)
    BodyFont.restyle(
      restyled, to: editorFont, mode: mode,
      bodyFamilies: EditorFontPolicy.bodyFamilies(for: settings))
    return restyled
  }
}
