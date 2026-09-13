import Foundation

/// Where everything lives on disk (specification §6.1).
///
/// ```
/// ~/Library/Application Support/Itchy/
/// ├── index.json                 slot order
/// ├── settings.json              non-secret preferences
/// └── pads.noindex/<uuid>/       excluded from Spotlight (D-16, NFR-3.4)
///     ├── content.rtfd/          authoritative styled content
///     ├── content.txt            shadow, derived, never read back
///     └── meta.json
/// ```
///
/// The `.noindex` suffix is the mechanism that actually works. D-10 specified
/// `.metadata_never_index`, which spike S-3 showed has no effect on a directory
/// — it is a volume-root marker. `.noindex` is what Xcode uses for DerivedData,
/// and it excludes the directory's contents from Spotlight while leaving them
/// perfectly readable to `grep`, to the shadow files' intended consumers, and to
/// the MCP server (D-16).
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
  /// `NFR-3.4`, D-16. The suffix is load-bearing: renaming this directory
  /// without it silently restores Spotlight indexing of every pad.
  public static let padsDirectoryName = "pads.noindex"

  /// Archives hold copies of pad content, so they carry the same suffix for the
  /// same reason. A backup that is indexed when the original is not would be a
  /// privacy hole opened by the thing meant to protect against data loss
  /// (D-18).
  public static let archivesDirectoryName = "archives.noindex"

  /// What the pads directory was called before D-16. Migrated on load.
  public static let legacyPadsDirectoryName = "pads"

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

  public var archivesDirectory: URL {
    root.appendingPathComponent(Self.archivesDirectoryName)
  }

  public func archiveDirectory(named name: String) -> URL {
    archivesDirectory.appendingPathComponent(name)
  }

  /// Where pads lived before D-16, so an existing install can be moved.
  public var legacyPadsDirectory: URL {
    root.appendingPathComponent(Self.legacyPadsDirectoryName)
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
