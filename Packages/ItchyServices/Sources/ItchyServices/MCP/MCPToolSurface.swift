import Foundation
import ItchyCore

/// The five tools, and nothing else (`FR-8.5`, §11.3).
///
/// The narrowness is the point, so the set is written down once, here, and the
/// count is asserted in a test. A sixth tool is a decision someone has to take
/// deliberately rather than a line someone adds.
///
/// That has happened once and the answer was no: D-30 declined a transform
/// tool, and withdrew the clause of `FR-9.2` that would have required one.
public enum MCPToolSurface {
  public static let listPads = "list_pads"
  public static let readPad = "read_pad"
  public static let appendPad = "append_pad"
  public static let writePad = "write_pad"
  public static let createPad = "create_pad"

  public struct ToolDescriptor: Sendable, Equatable {
    public let name: String
    public let description: String
    /// Property name to whether it is required.
    public let properties: [(name: String, required: Bool)]

    public static func == (lhs: ToolDescriptor, rhs: ToolDescriptor) -> Bool {
      lhs.name == rhs.name && lhs.description == rhs.description
        && lhs.properties.map(\.name) == rhs.properties.map(\.name)
        && lhs.properties.map(\.required) == rhs.properties.map(\.required)
    }
  }

  public static let all: [ToolDescriptor] = [
    ToolDescriptor(
      name: listPads,
      description: "List scratchpads exposed to agents.",
      properties: []),
    ToolDescriptor(
      name: readPad,
      description: "Read a pad's contents as plain text.",
      properties: [(name: "pad", required: true)]),
    ToolDescriptor(
      name: appendPad,
      description: "Append text to the end of a pad.",
      properties: [(name: "pad", required: true), (name: "text", required: true)]),
    ToolDescriptor(
      name: writePad,
      description: "Replace a pad's entire contents with plain text.",
      properties: [(name: "pad", required: true), (name: "text", required: true)]),
    ToolDescriptor(
      name: createPad,
      description: "Create a new pad if a slot is free.",
      properties: [(name: "name", required: false), (name: "text", required: false)]),
  ]

  /// The resource URI for a pad (`FR-8.1`, §11.3), so that a pad can be
  /// attached to a conversation rather than fetched by a tool call.
  public static func resourceURI(for id: PadID) -> String {
    "itchy://pad/\(id)"
  }

  /// The inverse, for a `resources/read`. Returns nil for anything that is not
  /// one of our URIs, rather than guessing.
  public static func padID(fromResourceURI uri: String) -> PadID? {
    let prefix = "itchy://pad/"
    guard uri.hasPrefix(prefix) else { return nil }
    return PadID(string: String(uri.dropFirst(prefix.count)))
  }
}
