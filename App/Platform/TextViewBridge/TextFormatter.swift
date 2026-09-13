import AppKit
import ItchyCore

/// Toggles bold, italic and underline on a text view (D-20).
///
/// Whether a toggle applies or removes is `FormattingPlan`'s decision; this
/// reads the selection and carries it out.
@MainActor
enum TextFormatter {
  /// The selection as runs, or the typing attributes when nothing is selected.
  static func runs(in textView: NSTextView) -> [RunFormat] {
    let ranges = selectedRanges(in: textView)
    guard let storage = textView.textStorage, !ranges.isEmpty else {
      return [format(of: textView.typingAttributes)]
    }
    var runs: [RunFormat] = []
    for range in ranges {
      storage.enumerateAttributes(in: range) { attributes, _, _ in
        runs.append(format(of: attributes))
      }
    }
    return runs
  }

  static func format(of attributes: [NSAttributedString.Key: Any]) -> RunFormat {
    let traits = (attributes[.font] as? NSFont).map { NSFontManager.shared.traits(of: $0) } ?? []
    let underline = attributes[.underlineStyle] as? Int ?? 0
    return RunFormat(
      isBold: traits.contains(.boldFontMask),
      isItalic: traits.contains(.italicFontMask),
      isUnderlined: underline != 0)
  }

  /// Toggles a trait over the selection as one undoable step, or on the typing
  /// attributes when nothing is selected.
  ///
  /// A selection change goes through `shouldChangeText` and `didChangeText`, so
  /// the text view records undo and the coordinator stages the pad exactly as it
  /// would for a keystroke.
  static func toggle(_ trait: FormatTrait, in textView: NSTextView, fallbackFont: NSFont) {
    let change = FormattingPlan.change(toggling: trait, runs: runs(in: textView))
    let ranges = selectedRanges(in: textView)
    guard !ranges.isEmpty else {
      textView.typingAttributes = applying(
        change, trait, to: textView.typingAttributes, fallbackFont: fallbackFont)
      return
    }
    guard let storage = textView.textStorage,
      textView.shouldChangeText(
        inRanges: ranges.map { NSValue(range: $0) }, replacementStrings: nil)
    else { return }

    var pieces: [(range: NSRange, attributes: [NSAttributedString.Key: Any])] = []
    for range in ranges {
      storage.enumerateAttributes(in: range) { attributes, subrange, _ in
        pieces.append(
          (subrange, applying(change, trait, to: attributes, fallbackFont: fallbackFont)))
      }
    }
    storage.beginEditing()
    for piece in pieces {
      storage.setAttributes(piece.attributes, range: piece.range)
    }
    storage.endEditing()
    textView.undoManager?.setActionName(FormattingPlan.actionName(for: trait))
    textView.didChangeText()
  }

  static func applying(
    _ change: FormattingPlan.Change,
    _ trait: FormatTrait,
    to attributes: [NSAttributedString.Key: Any],
    fallbackFont: NSFont
  ) -> [NSAttributedString.Key: Any] {
    var result = attributes
    let font = attributes[.font] as? NSFont ?? fallbackFont
    switch (trait, change) {
    case (.bold, _):
      result[.font] = converted(font, trait: .boldFontMask, change: change)
    case (.italic, _):
      result[.font] = converted(font, trait: .italicFontMask, change: change)
    case (.underline, .apply):
      result[.underlineStyle] = NSUnderlineStyle.single.rawValue
    case (.underline, .remove):
      result[.underlineStyle] = nil
    }
    return result
  }

  private static func converted(
    _ font: NSFont,
    trait: NSFontTraitMask,
    change: FormattingPlan.Change
  ) -> NSFont {
    switch change {
    case .apply: NSFontManager.shared.convert(font, toHaveTrait: trait)
    case .remove: NSFontManager.shared.convert(font, toNotHaveTrait: trait)
    }
  }

  private static func selectedRanges(in textView: NSTextView) -> [NSRange] {
    textView.selectedRanges.map(\.rangeValue).filter { $0.length > 0 }
  }
}
