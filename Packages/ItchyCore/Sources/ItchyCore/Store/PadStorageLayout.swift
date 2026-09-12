import Foundation

/// Where everything lives on disk (specification §6.1).
///
/// ```
/// ~/Library/Application Support/Itchy/
/// ├── .metadata_never_index      D-10, NFR-3.4
/// ├── index.json                 slot order
/// ├── settings.json              non-secret preferences
/// └── pads/<uuid>/
///     ├── content.rtfd/          authoritative styled content
///     ├── content.txt            shadow, derived, never read back
///     └── meta.json
/// ```
///
/// Flat files, one directory per pad, no database. For twenty records SQLite
/// through Core Data or SwiftData is overhead in exchange for capabilities that
/// will never be used, and it makes the content opaque to every other tool on
/// the machine — which matters more than usual given where this is going.
public struct PadStorageLayout: Sendable {
  public static let contentDirectoryName = "content.rtfd"
  public static let shadowFileName = "content.txt"
  public static let metadataFileName = "meta.json"
  public static let indexFileName = "index.json"
  public static let settingsFileName = "settings.json"
  public static let spotlightExclusionName = ".metadata_never_index"
  public static let padsDirectoryName = "pads"

  public let root: URL

  public init(root: URL) {
    self.root = root
  }

  /// The default location, under Application Support.
  public static func standard() throws -> PadStorageLayout {
    let support = try FileManager.default.url(
      for: .applicationSupportDirectory, in: .userDomainMask,
      appropriateFor: nil, create: true)
    return PadStorageLayout(root: support.appendingPathComponent("Itchy"))
  }

  /// A layout rooted at an arbitrary path.
  ///
  /// Exists so that `itchyctl` can point at a scratch directory without
  /// constructing file URLs itself, which `CON-4` and `Scripts/arch-lint.sh`
  /// both forbid outside the store.
  public static func at(path: String) -> PadStorageLayout {
    PadStorageLayout(root: URL(fileURLWithPath: path))
  }

  public var padsDirectory: URL {
    root.appendingPathComponent(Self.padsDirectoryName)
  }

  public var indexFile: URL {
    root.appendingPathComponent(Self.indexFileName)
  }

  public var settingsFile: URL {
    root.appendingPathComponent(Self.settingsFileName)
  }

  /// The marker that keeps pad contents out of system-wide search
  /// (`NFR-3.4`, D-10). Command-line and agent readability of the shadow files
  /// is intended; appearing in a user's Spotlight results is not.
  public var spotlightExclusionFile: URL {
    root.appendingPathComponent(Self.spotlightExclusionName)
  }

  public func directory(for id: PadID) -> URL {
    padsDirectory.appendingPathComponent(id.directoryName)
  }

  public func contentDirectory(for id: PadID) -> URL {
    directory(for: id).appendingPathComponent(Self.contentDirectoryName)
  }

  public func shadowFile(for id: PadID) -> URL {
    directory(for: id).appendingPathComponent(Self.shadowFileName)
  }

  public func metadataFile(for id: PadID) -> URL {
    directory(for: id).appendingPathComponent(Self.metadataFileName)
  }
}
