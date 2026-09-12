import Foundation

/// Atomic replacement of a file or a directory (`FR-5.6`, specification §6.3).
///
/// Specified as a procedure rather than described, because `NFR-2.1` turns on it
/// being right:
///
/// 1. Create the temporary in the *same directory* as the target, so that the
///    replacement is within one filesystem.
/// 2. Write the full contents and synchronise before closing. Without the sync
///    the replacement can be durable while the contents are not, which is the
///    failure that produces a zero-length pad after a power loss.
/// 3. Replace.
/// 4. On any failure, unlink the temporary and surface the error. The target is
///    untouched by construction.
public struct AtomicWrite: Sendable {
  private let fileSystem: any FileSystemOperations

  public init(fileSystem: any FileSystemOperations) {
    self.fileSystem = fileSystem
  }

  /// Writes `data` to `url`, atomically.
  public func write(_ data: Data, to url: URL) throws {
    let temporary = Self.temporaryURL(beside: url)
    do {
      try fileSystem.write(data, to: temporary)
      try fileSystem.replaceItem(at: url, with: temporary)
    } catch {
      try? fileSystem.removeItem(at: temporary)
      throw error
    }
  }

  /// Writes a directory of files to `url`, atomically.
  ///
  /// The whole bundle is written to a sibling temporary directory and the
  /// directory itself is then replaced. `replaceItemAt` handles directories and
  /// the same guarantee applies, which is what makes an RTFD bundle no less safe
  /// to write than a flat file (specification §6.3).
  public func writeDirectory(_ files: [String: Data], to url: URL) throws {
    let temporary = Self.temporaryURL(beside: url)
    do {
      try fileSystem.createDirectory(at: temporary)
      for (name, data) in files.sorted(by: { $0.key < $1.key }) {
        try fileSystem.write(data, to: temporary.appendingPathComponent(name))
      }
      try fileSystem.replaceItem(at: url, with: temporary)
    } catch {
      try? fileSystem.removeItem(at: temporary)
      throw error
    }
  }

  /// Reads a directory of files back into a filename-to-bytes map.
  public func readDirectory(at url: URL) throws -> [String: Data] {
    var result: [String: Data] = [:]
    for child in try fileSystem.contentsOfDirectory(at: url) {
      guard !fileSystem.isDirectory(at: child) else { continue }
      result[child.lastPathComponent] = try fileSystem.contents(of: child)
    }
    return result
  }

  /// Removes temporaries left behind by an interrupted write.
  ///
  /// Run at startup over the support directory. One hour is long enough that a
  /// write in progress is never swept, and short enough that debris does not
  /// accumulate (specification §6.3).
  public func sweepOrphanedTemporaries(in directory: URL, olderThan age: TimeInterval, now: Date) {
    guard let children = try? fileSystem.contentsOfDirectory(at: directory) else { return }
    for child in children {
      guard Self.isTemporary(child) else { continue }
      guard let modified = try? fileSystem.modificationDate(of: child) else { continue }
      guard now.timeIntervalSince(modified) > age else { continue }
      try? fileSystem.removeItem(at: child)
    }
  }

  /// Temporary names are hidden, carry the process id, and end in `.tmp`, so
  /// that a sweep can recognise its own debris without guessing.
  internal static func temporaryURL(beside target: URL) -> URL {
    let name =
      ".\(target.lastPathComponent).\(ProcessInfo.processInfo.processIdentifier)"
      + ".\(UUID().uuidString.prefix(8)).tmp"
    return target.deletingLastPathComponent().appendingPathComponent(name)
  }

  internal static func isTemporary(_ url: URL) -> Bool {
    let name = url.lastPathComponent
    return name.hasPrefix(".") && name.hasSuffix(".tmp")
  }
}
