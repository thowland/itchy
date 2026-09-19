import Foundation
import ItchyCore

/// What an agent's write does to the pad's text (`FR-8.8`, §11.6).
///
/// The two write tools differ only in what they replace, so the difference is a
/// value and the applier takes it rather than having two nearly identical
/// paths. Naming it also gives the undo step a name, which is the point of
/// `FR-8.8`: the person must be able to see what happened and revert it in one
/// step, and "Undo" with no noun is not that.
enum AgentWrite: Equatable, Sendable {
  case replaceAll
  case append
}

enum AgentWritePlan {
  /// The range the replacement covers.
  static func range(for write: AgentWrite, length: Int) -> NSRange {
    switch write {
    case .replaceAll: NSRange(location: 0, length: length)
    case .append: NSRange(location: length, length: 0)
    }
  }

  /// What the Edit menu says, and what the banner says happened.
  ///
  /// The client is named when it gave one. "Undo Write from claude" tells the
  /// person which of the things running on their machine did this; "Undo Agent
  /// Write" tells them only that one of them did.
  static func actionName(for write: AgentWrite, origin: WriteOrigin) -> String {
    let verb = write == .append ? "Append" : "Write"
    guard case .mcp(let client) = origin, let client, !client.isEmpty else {
      return "Agent \(verb)"
    }
    return "\(verb) from \(client)"
  }
}
