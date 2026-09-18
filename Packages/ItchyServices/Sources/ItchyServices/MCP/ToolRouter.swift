import Foundation
import ItchyCore

/// What a tool call resolves to, once the arguments have been understood
/// (§11.3, §15.2).
///
/// A value, not a call. The router decides which store operation a request
/// means and never performs it, which is what lets the whole tool surface be
/// tested without a socket, a store or an agent.
public enum MCPOperation: Sendable, Equatable {
  case listPads
  case readPad(PadID)
  case appendPad(PadID, text: String)
  case writePad(PadID, text: String)
  case createPad(name: String?, text: String?)
}

/// Why a tool call could not be routed.
///
/// `padNotFound` deliberately covers both a pad that does not exist and one the
/// caller may not see (§11.5). They are the same answer because distinguishing
/// them would let the tool surface confirm the existence of pads the caller has
/// not been given.
public enum MCPRoutingError: Error, Sendable, Equatable {
  case unknownTool(String)
  case missingArgument(name: String, tool: String)
  case padNotFound(reference: String)
  case ambiguousPad(reference: String, candidates: [String])

  /// Shown to the agent, so it says what to do differently.
  public var message: String {
    switch self {
    case .unknownTool(let name):
      return "There is no tool called '\(name)'."
    case .missingArgument(let name, let tool):
      return "'\(tool)' needs a '\(name)' argument."
    case .padNotFound(let reference):
      return "No pad called '\(reference)' is available."
    case .ambiguousPad(let reference, let candidates):
      return "'\(reference)' matches more than one pad: \(candidates.joined(separator: ", ")). "
        + "Use the pad's identifier instead."
    }
  }
}

/// Turns a tool name and its arguments into an operation (§15.2).
public enum ToolRouter {
  public static func route(
    tool: String,
    arguments: [String: String],
    visiblePads: [PadMetadata]
  ) throws -> MCPOperation {
    switch tool {
    case MCPToolSurface.listPads:
      return .listPads
    case MCPToolSurface.readPad:
      return .readPad(try pad(from: arguments, tool: tool, in: visiblePads))
    case MCPToolSurface.appendPad:
      return .appendPad(
        try pad(from: arguments, tool: tool, in: visiblePads),
        text: try text(from: arguments, tool: tool))
    case MCPToolSurface.writePad:
      return .writePad(
        try pad(from: arguments, tool: tool, in: visiblePads),
        text: try text(from: arguments, tool: tool))
    case MCPToolSurface.createPad:
      // Both arguments are optional: §11.3's schema requires neither, and a pad
      // with no name gets one the way a pad created from the menu does.
      return .createPad(name: arguments["name"], text: arguments["text"])
    default:
      throw MCPRoutingError.unknownTool(tool)
    }
  }

  private static func pad(
    from arguments: [String: String], tool: String, in pads: [PadMetadata]
  ) throws -> PadID {
    guard let reference = arguments["pad"] else {
      throw MCPRoutingError.missingArgument(name: "pad", tool: tool)
    }
    switch PadResolver.resolve(reference, in: pads) {
    case .resolved(let id):
      return id
    case .notFound:
      throw MCPRoutingError.padNotFound(reference: reference)
    case .ambiguous(let candidates):
      throw MCPRoutingError.ambiguousPad(reference: reference, candidates: candidates)
    }
  }

  private static func text(from arguments: [String: String], tool: String) throws -> String {
    guard let text = arguments["text"] else {
      throw MCPRoutingError.missingArgument(name: "text", tool: tool)
    }
    return text
  }
}
