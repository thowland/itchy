import SwiftUI

/// Row title and key equivalent.
///
/// A seam, not a view helper: deciding that a faulted pad reads "⚠︎ unreadable"
/// and that a pinned one carries a marker is a decision, and decisions do not
/// live in view files (D-11, specification §15.2). The complexity cap on
/// coverage-excluded files is what moved this here.
enum MenuRowLabel {
  static func text(for row: MenuRow) -> String {
    var title = row.name
    if row.isFaulted {
      title += "  ⚠︎ unreadable"
    }
    if row.hasUnseenExternalWrite {
      title += "  ✳︎ written"
    }
    if let marker = row.sizeMarker {
      title += "  \(marker)"
    }
    if row.isPinned {
      title = "📌 " + title
    }
    return title
  }

  static func shortcut(for row: MenuRow) -> KeyEquivalent {
    guard let key = row.keyEquivalent, let character = key.first else { return .space }
    return KeyEquivalent(character)
  }
}
