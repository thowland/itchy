import Foundation
import ItchyCore

/// Namespace marker for the services module.
///
/// Transforms arrive in Sprint 6, the MCP server in Sprint 8 and model routing
/// in Sprint 10. The module exists from Sprint 0 so that the layer boundary is
/// established before there is any pressure to put a service somewhere else.
public enum ItchyServices {
  /// The services layer reads the schema version through Core, never directly,
  /// which is the dependency direction the layering requires.
  public static var schemaVersion: Int { ItchyCore.schemaVersion }
}
