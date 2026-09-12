import Foundation

/// What caused a content change.
///
/// Carried on change events and on the external-write marker so that the
/// interface can distinguish the user's own editing from a transform or an agent
/// write without inspecting the content.
public enum WriteOrigin: Sendable, Codable, Equatable, Hashable {
  case user
  case transform(String)
  case mcp(client: String?)

  /// Whether a write from this origin should be surfaced to the user as
  /// something that happened to the pad rather than something they did.
  public var isExternal: Bool {
    switch self {
    case .user: false
    case .transform, .mcp: true
    }
  }
}
