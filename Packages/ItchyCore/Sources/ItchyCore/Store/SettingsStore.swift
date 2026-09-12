import Foundation

/// Reads and writes `settings.json`.
///
/// Lives under `Store/` because it touches disk, and `CON-4` puts every disk
/// access in one place — `Scripts/arch-lint.sh` enforces that textually.
public struct SettingsStore: Sendable {
  private let layout: PadStorageLayout
  private let fileSystem: any FileSystemOperations
  private let atomic: AtomicWrite

  public init(layout: PadStorageLayout, fileSystem: any FileSystemOperations = LocalFileSystem()) {
    self.layout = layout
    self.fileSystem = fileSystem
    self.atomic = AtomicWrite(fileSystem: fileSystem)
  }

  /// Loads settings, clamping anything out of range and writing the correction
  /// back so that the file stops lying (`FR-2.1`).
  ///
  /// A settings file that cannot be read is replaced by defaults rather than
  /// being allowed to prevent launch (`NFR-2.2`). Losing a preference is
  /// recoverable; refusing to start is not.
  public func load() -> AppSettings {
    guard fileSystem.fileExists(at: layout.settingsFile) else { return AppSettings() }
    guard let data = try? fileSystem.contents(of: layout.settingsFile),
      let decoded = try? JSONCoding.decoder().decode(AppSettings.self, from: data)
    else {
      return AppSettings()
    }
    let clamped = decoded.clamped()
    if decoded.needsRewrite {
      try? save(clamped)
    }
    return clamped
  }

  public func save(_ settings: AppSettings) throws {
    try fileSystem.createDirectory(at: layout.root)
    let data = try JSONCoding.encoder().encode(settings.clamped())
    try atomic.write(data, to: layout.settingsFile)
  }
}
