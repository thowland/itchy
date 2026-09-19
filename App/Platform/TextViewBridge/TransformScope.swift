import Foundation
import ItchyServices

/// Whether a transform acts on the selection or on the whole pad (`FR-6.4`,
/// §7.3 step 1).
///
/// One line of rule, extracted because it is the rule the acceptance criterion
/// names — pretty-printing with a fragment selected must leave the surrounding
/// text untouched — and testing it should not require a window (D-11).
enum TransformScope {
  /// UTF-16 offsets, because that is what `NSTextView` reports a selection in
  /// and what it will be handed back.
  static func scope(forSelectionLength length: Int, at location: Int) -> Scope {
    guard length > 0 else { return .wholePad }
    return .selection(location..<(location + length))
  }

  static func range(of scope: Scope, wholeLength: Int) -> NSRange {
    switch scope {
    case .wholePad: return NSRange(location: 0, length: wholeLength)
    case .selection(let bounds):
      return NSRange(location: bounds.lowerBound, length: bounds.count)
    }
  }
}
