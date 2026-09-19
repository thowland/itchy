import ItchyCore
import ItchyServices
import SwiftUI

/// What the Transform menu shows (D-11, `FR-6.3`).
///
/// The menu is built from a survey rather than from a filtered list: a transform
/// that does not apply is shown disabled, carrying the reason as its help text,
/// so that the menu's shape does not change under the cursor and so that "why
/// can I not pretty-print this?" has an answer in the place the question is
/// asked.
enum TransformMenuModel {
  struct Row: Identifiable, Equatable {
    let id: String
    let title: String
    let isEnabled: Bool
    /// The refusal, shown on hover. `nil` when the row is enabled.
    let reason: String?
  }

  static func rows(for input: TransformInput) -> [[Row]] {
    TransformRegistry.groups.map { group in
      group.map { transform in
        row(for: transform, applicability: transform.applicability(to: input))
      }
    }
  }

  static func row(for transform: any Transform, applicability: Applicability) -> Row {
    switch applicability {
    case .applicable:
      return Row(id: transform.id, title: transform.title, isEnabled: true, reason: nil)
    case .notApplicable(let reason):
      return Row(id: transform.id, title: transform.title, isEnabled: false, reason: reason)
    }
  }

  /// Whether the menu is worth opening at all. A pad with nothing in it offers
  /// nothing, and a menu of twelve disabled rows is worse than a disabled menu.
  static func isEnabled(for rows: [[Row]]) -> Bool {
    rows.contains { group in group.contains(where: \.isEnabled) }
  }
}
