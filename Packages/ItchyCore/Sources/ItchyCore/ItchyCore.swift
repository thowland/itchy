import Foundation

/// Namespace marker for the core module.
///
/// Sprint 0 deliberately ships no domain logic; the model, store and transform
/// protocol arrive in Sprint 1. This exists so that the module, its test target
/// and the coverage pipeline are all exercised end to end before there is
/// anything at stake in them.
public enum ItchyCore {
  /// Schema version written into every JSON file on disk (D-7).
  public static let schemaVersion = 1
}
