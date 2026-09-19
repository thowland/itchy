import Foundation
import ItchyCore

/// Validation and wording for a pad's own settings (D-11, D-21).
enum PadSettingsModel {
  enum NameChange: Equatable, Sendable {
    case rename(String)
    case unchanged
  }

  /// A pad always has a name (`FR-2.4`), so clearing the field keeps the one it
  /// has rather than saving an empty one. Surrounding whitespace is trimmed: a
  /// trailing space is invisible in a menu and fatal to asking for a pad by name.
  static func nameChange(draft: String, current: String) -> NameChange {
    let trimmed = trimmed(draft)
    guard !trimmed.isEmpty, trimmed != current else { return .unchanged }
    return .rename(trimmed)
  }

  /// Said rather than enforced. `FR-2.4` lets names repeat, and the cost of a
  /// repeat is only that the pad cannot be asked for by name, which is the thing
  /// an agent will do.
  static func notice(draft: String, padID: PadID, pads: [PadMetadata]) -> String? {
    let name = trimmed(draft)
    guard !name.isEmpty else {
      return "A pad always has a name. Leaving this empty keeps the current one."
    }
    // Case-insensitive, because that is how an agent's name is resolved
    // (specification §11.5).
    let isShared = pads.contains {
      $0.id != padID && $0.name.caseInsensitiveCompare(name) == .orderedSame
    }
    guard isShared else { return nil }
    return "Another pad is also called “\(name)”. Both still work from the menu, "
      + "but an agent asking for this pad by name cannot tell them apart."
  }

  static let pinnedLabel = "Reopen this pad when Itchy starts"

  /// What a pad's routing control says (`FR-9.1`, `FR-9.3`).
  static let routingLabel = "Model work on this pad"

  static func routingChoice(_ policy: RoutingPolicy) -> String {
    switch policy {
    case .localOnly: "Local only — never leaves this Mac"
    case .remotePermitted: "May use a remote service"
    case .askEachTime: "Ask me each time"
    }
  }

  /// Said under the control, because "local only" is the default and the
  /// consequence of changing it is the one thing worth being sure about.
  static func routingNote(_ policy: RoutingPolicy) -> String? {
    switch policy {
    case .localOnly:
      return nil
    case .remotePermitted:
      return "Transforms that need a remote model may send this pad's text to it."
    case .askEachTime:
      return "Itchy will ask before any of this pad's text leaves the machine."
    }
  }

  static func title(for pad: PadMetadata) -> String {
    "Settings for “\(pad.name)”"
  }

  private static func trimmed(_ name: String) -> String {
    name.trimmingCharacters(in: .whitespacesAndNewlines)
  }
}
