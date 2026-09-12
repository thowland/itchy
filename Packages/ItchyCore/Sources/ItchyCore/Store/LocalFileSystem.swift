import Foundation

/// The real filesystem.
///
/// The only type in the project permitted to touch `FileManager` (`CON-4`),
/// which `Scripts/arch-lint.sh` enforces textually by refusing that symbol
/// outside `Store/`.
public struct LocalFileSystem: FileSystemOperations {
  /// `FileManager.default` is documented as safe to use from multiple threads
  /// for these operations, but the type is not `Sendable`, so it is reached
  /// through a computed property rather than stored. Storing it would make this
  /// struct's `Sendable` conformance a claim the compiler cannot check.
  private var manager: FileManager { .default }

  public init() {}

  public func fileExists(at url: URL) -> Bool {
    manager.fileExists(atPath: url.path)
  }

  public func isDirectory(at url: URL) -> Bool {
    var isDir = ObjCBool(false)
    let exists = manager.fileExists(atPath: url.path, isDirectory: &isDir)
    return exists && isDir.boolValue
  }

  public func contents(of url: URL) throws -> Data {
    try Data(contentsOf: url)
  }

  /// Writes with an `fsync` before the descriptor closes.
  ///
  /// Without the sync a replacement can be durable while its contents are not,
  /// which is the failure that produces a zero-length pad after a power loss
  /// (specification §6.3, step 2).
  public func write(_ data: Data, to url: URL) throws {
    try data.write(to: url, options: .atomic)
    let handle = try FileHandle(forWritingTo: url)
    defer { try? handle.close() }
    try handle.synchronize()
  }

  public func createDirectory(at url: URL) throws {
    try manager.createDirectory(at: url, withIntermediateDirectories: true)
  }

  public func removeItem(at url: URL) throws {
    try manager.removeItem(at: url)
  }

  public func replaceItem(at destination: URL, with replacement: URL) throws {
    if manager.fileExists(atPath: destination.path) {
      _ = try manager.replaceItemAt(destination, withItemAt: replacement)
    } else {
      try manager.moveItem(at: replacement, to: destination)
    }
  }

  public func contentsOfDirectory(at url: URL) throws -> [URL] {
    try manager.contentsOfDirectory(at: url, includingPropertiesForKeys: nil)
  }

  public func modificationDate(of url: URL) throws -> Date {
    let attributes = try manager.attributesOfItem(atPath: url.path)
    guard let date = attributes[.modificationDate] as? Date else {
      throw CocoaError(.fileReadUnknown)
    }
    return date
  }

  public func sizeOfItem(at url: URL) throws -> Int {
    if isDirectory(at: url) {
      let children = try contentsOfDirectory(at: url)
      return try children.reduce(0) { try $0 + sizeOfItem(at: $1) }
    }
    let attributes = try manager.attributesOfItem(atPath: url.path)
    return (attributes[.size] as? Int) ?? 0
  }
}
