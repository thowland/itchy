import Foundation

/// Forward migration of on-disk JSON (specification §6.5).
///
/// Every file carries a `schemaVersion`. A version below current is passed
/// through an ordered list of migrations; a version above current causes that pad
/// to be reported unreadable rather than guessed at (`FR-5.8`).
///
/// The list ships empty at version 1. The machinery exists now anyway, because
/// adding it later means writing migrations for files that predate the
/// versioning, which is the one situation it cannot help with.
public struct SchemaMigration: Sendable {
  public let from: Int
  public let to: Int
  public let apply: @Sendable ([String: JSONValue]) -> [String: JSONValue]

  public init(
    from: Int,
    to: Int,
    apply: @escaping @Sendable ([String: JSONValue]) -> [String: JSONValue]
  ) {
    self.from = from
    self.to = to
    self.apply = apply
  }
}

/// Applies the registered migrations in order.
public struct SchemaMigrator: Sendable {
  public enum Outcome: Sendable, Equatable {
    /// Already at the current version; nothing was changed.
    case current
    /// Migrated up from an older version.
    case migrated(from: Int)
    /// Written by a newer build than this one.
    case tooNew(found: Int, supported: Int)
  }

  public let current: Int
  public let migrations: [SchemaMigration]

  public init(current: Int = ItchyCore.schemaVersion, migrations: [SchemaMigration] = []) {
    self.current = current
    self.migrations = migrations
  }

  /// Reads the version out of a decoded object, defaulting to 1 when absent.
  ///
  /// Absent rather than invalid is treated as version 1 because the very first
  /// files this application ever wrote carry the field, so a missing field means
  /// a hand-written file and version 1 is the charitable reading.
  public func version(of object: [String: JSONValue]) -> Int {
    guard case .number(let value)? = object["schemaVersion"] else { return 1 }
    return Int(value)
  }

  public func migrate(
    _ object: [String: JSONValue]
  ) -> (object: [String: JSONValue], outcome: Outcome) {
    let found = version(of: object)
    if found > current {
      return (object, .tooNew(found: found, supported: current))
    }
    if found == current {
      return (object, .current)
    }
    var result = object
    var at = found
    while at < current {
      guard let step = migrations.first(where: { $0.from == at }) else { break }
      result = step.apply(result)
      at = step.to
    }
    result["schemaVersion"] = .number(Double(current))
    return (result, .migrated(from: found))
  }
}
