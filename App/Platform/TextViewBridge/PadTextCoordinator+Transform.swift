import AppKit
import ItchyCore
import ItchyServices

/// The text view's half of a transform: gathering the input, and putting the
/// output back (§7.3 steps 1 and 4).
///
/// Neither half decides anything. What scope applies is `TransformScope`'s,
/// what the replacement looks like is `TransformStylePlan`'s, and whether the
/// transform may run at all is `TransformRunner`'s.
extension PadTextCoordinator {
  /// Step 1: the text in scope, the selection if there is one.
  func transformInput() -> TransformInput? {
    guard let textView = textView else { return nil }
    let text = textView.string as NSString
    let selection = textView.selectedRange()
    let scope = TransformScope.scope(forSelectionLength: selection.length, at: selection.location)
    let inScope = TransformScope.range(of: scope, wholeLength: text.length)
    return TransformInput(
      plainText: text.substring(with: inScope),
      rtfd: nil,
      scope: scope,
      padMode: textView.mode)
  }

  /// Step 4: one grouped, named undo step, so the Edit menu reads "Undo
  /// Pretty-print JSON" (`FR-6.5`).
  ///
  /// A report is shown, never applied, so it does not arrive here.
  func applyTransform(_ output: TransformOutput, scope: Scope, transformID: String, actionName: String) {
    guard let textView = textView else { return }
    guard case .plainText(let replacement) = output else { return }
    let style = TransformStylePlan.style(forTransform: transformID, mode: textView.mode)
    let range = TransformScope.range(of: scope, wholeLength: (textView.string as NSString).length)
    let attributes = Self.attributes(for: style, in: textView, at: range.location)
    apply(
      NSAttributedString(string: replacement, attributes: attributes),
      over: range,
      actionName: actionName)
  }

  private static func attributes(
    for style: TransformStylePlan.Style, in textView: PadTextView, at location: Int
  ) -> [NSAttributedString.Key: Any] {
    switch style {
    case .bodyFontOnly:
      return [.font: textView.bodyFont]
    case .inheritFromRangeStart:
      guard let storage = textView.textStorage, storage.length > location else {
        return [.font: textView.bodyFont]
      }
      return storage.attributes(at: location, effectiveRange: nil)
    }
  }
}
