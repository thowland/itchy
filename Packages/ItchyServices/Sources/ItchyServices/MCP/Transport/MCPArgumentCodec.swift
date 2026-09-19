import Foundation
import ItchyCore
import MCP

/// Converts the SDK's arguments into the strings the router takes (§11.3).
///
/// The router is deliberately free of SDK types, so that the whole tool surface
/// is testable without a transport, a socket or an agent. The price of that is a
/// conversion, and this is it — the only place in the server where the boundary
/// is crossed in this direction.
///
/// Everything becomes a string, because every argument the five tools take *is*
/// a string. A client that sends `{"pad": 3}` gets `"3"` rather than a type
/// error, which is the reading an agent meant; a client that sends an object
/// gets nothing, because there is no reading of that which is likely to be what
/// it meant.
public enum MCPArgumentCodec {
  public static func strings(from arguments: [String: Value]?) -> [String: String] {
    guard let arguments else { return [:] }
    return arguments.reduce(into: [String: String]()) { result, entry in
      guard let string = scalar(entry.value) else { return }
      result[entry.key] = string
    }
  }

  internal static func scalar(_ value: Value) -> String? {
    switch value {
    case .string(let string): string
    case .int(let number): String(number)
    case .double(let number): String(number)
    case .bool(let flag): flag ? "true" : "false"
    case .null, .array, .object, .data: nil
    }
  }
}

/// Turns what `MCPService` produced into what the SDK returns (§11.3).
///
/// A projection, so that "what an agent sees" is a value a test can compare
/// rather than something observable only through a client.
public enum MCPResultCodec {
  public static func content(for result: MCPResult) -> [Tool.Content] {
    [.text(text: text(for: result), annotations: nil, _meta: nil)]
  }

  public static func text(for result: MCPResult) -> String {
    switch result {
    case .text(let text):
      return text
    case .padList(let summaries):
      return summaries.isEmpty ? emptyListing : listing(summaries)
    case .created(let summary):
      return "Created “\(summary.name)” (\(summary.id)), readable at \(summary.uri)."
    }
  }

  /// Said rather than left blank. An empty list from a server that is running is
  /// indistinguishable from a server that is broken unless it explains itself,
  /// and the explanation is also the instruction: exposure is per pad and off by
  /// default (`NFR-3.2`).
  public static let emptyListing =
    "No pads are exposed to agents. Each pad is opted in individually, in its "
    + "own settings, and none is by default."

  private static func listing(_ summaries: [PadSummary]) -> String {
    summaries.map { summary in
      "\(summary.name) — \(summary.characters) characters — \(summary.uri)"
    }
    .joined(separator: "\n")
  }
}

/// The five tools as the SDK describes them (`FR-8.5`, §11.3).
///
/// The set is `MCPToolSurface`'s and is not restated here; this is the schema
/// that goes on the wire for it, derived from the descriptors so that adding a
/// tool in one place and forgetting the other is not possible.
public enum MCPToolCodec {
  public static var tools: [Tool] {
    MCPToolSurface.all.map { descriptor in
      Tool(
        name: descriptor.name,
        description: descriptor.description,
        inputSchema: schema(for: descriptor),
        annotations: annotations(for: descriptor.name))
    }
  }

  internal static func schema(for descriptor: MCPToolSurface.ToolDescriptor) -> Value {
    var properties: [String: Value] = [:]
    var required: [Value] = []
    for property in descriptor.properties {
      properties[property.name] = .object([
        "type": .string("string"),
        "description": .string(propertyDescription(property.name)),
      ])
      if property.required { required.append(.string(property.name)) }
    }
    return .object([
      "type": .string("object"),
      "properties": .object(properties),
      "required": .array(required),
    ])
  }

  /// Hints, and marked as such by the SDK. They are worth setting because a
  /// client that shows the user what a tool will do gets it right only if the
  /// server says: reading a pad changes nothing, writing one replaces what was
  /// there.
  internal static func annotations(for tool: String) -> Tool.Annotations {
    switch tool {
    case MCPToolSurface.listPads, MCPToolSurface.readPad:
      Tool.Annotations(readOnlyHint: true, openWorldHint: false)
    case MCPToolSurface.writePad:
      Tool.Annotations(readOnlyHint: false, destructiveHint: true, openWorldHint: false)
    default:
      Tool.Annotations(readOnlyHint: false, destructiveHint: false, openWorldHint: false)
    }
  }

  internal static func propertyDescription(_ name: String) -> String {
    switch name {
    case "pad": "The pad's name or identifier."
    case "text": "Plain text. Styling is not carried over this surface."
    case "name": "A name for the new pad. One is chosen if this is omitted."
    default: name
    }
  }
}
