import Foundation

/// Takes and prunes archives of the pads directory (D-18).
///
/// Under `Store/` because it touches disk, which `CON-4` confines to one place.
/// It copies the whole pads tree — `meta.json`, the shadow text, and the RTFD
/// bundles with their images — so an archive is restored by copying a directory
/// back, with no tooling required and nothing to go wrong in a restore path that
/// would only ever run when something had already gone wrong.
public struct ArchiveStore: Sendable {
  private let layout: PadStorageLayout
  private let fileSystem: any FileSystemOperations

  public init(layout: PadStorageLayout, fileSystem: any FileSystemOperations = LocalFileSystem()) {
    self.layout = layout
    self.fileSystem = fileSystem
  }

  /// Every archive present, oldest first.
  public func archives() -> [PadArchive] {
    guard let entries = try? fileSystem.contentsOfDirectory(at: layout.archivesDirectory) else {
      return []
    }
    return
      entries
      .filter { fileSystem.isDirectory(at: $0) }
      .compactMap { url in
        let name = url.lastPathComponent
        guard let taken = ArchivePolicy.date(fromDirectoryName: name) else { return nil }
        let pads =
          (try? fileSystem.contentsOfDirectory(at: url.appendingPathComponent("pads")))?
          .filter { fileSystem.isDirectory(at: $0) }.count ?? 0
        let bytes = (try? fileSystem.sizeOfItem(at: url)) ?? 0
        return PadArchive(id: name, taken: taken, padCount: pads, byteCount: bytes)
      }
      .sorted()
  }

  /// Total size of everything kept, which is what the settings window shows so
  /// the cost of the setting is visible rather than implied.
  public func totalBytes() -> Int {
    archives().reduce(0) { $0 + $1.byteCount }
  }

  /// Copies the pads directory and the index into a new timestamped archive.
  ///
  /// Returns nil when there is nothing to archive, which is not a failure: a
  /// store with no pads has nothing worth keeping.
  @discardableResult
  public func takeArchive(now: Date) throws -> PadArchive? {
    guard fileSystem.isDirectory(at: layout.padsDirectory) else { return nil }
    let pads =
      (try? fileSystem.contentsOfDirectory(at: layout.padsDirectory))?
      .filter { fileSystem.isDirectory(at: $0) } ?? []
    guard !pads.isEmpty else { return nil }

    let name = ArchivePolicy.directoryName(for: now)
    let destination = layout.archiveDirectory(named: name)
    guard !fileSystem.fileExists(at: destination) else {
      return archives().first { $0.id == name }
    }

    try fileSystem.createDirectory(at: layout.archivesDirectory)
    // Assembled beside the target and moved into place, so an interrupted
    // archive never leaves a half-written one that looks complete.
    let staging = layout.archiveDirectory(named: ".\(name).partial")
    try? fileSystem.removeItem(at: staging)
    try fileSystem.createDirectory(at: staging)

    do {
      try fileSystem.cloneItem(
        at: layout.padsDirectory, to: staging.appendingPathComponent("pads"))
      if fileSystem.fileExists(at: layout.indexFile) {
        try fileSystem.cloneItem(
          at: layout.indexFile, to: staging.appendingPathComponent("index.json"))
      }
      try fileSystem.replaceItem(at: destination, with: staging)
    } catch {
      try? fileSystem.removeItem(at: staging)
      throw error
    }

    let bytes = (try? fileSystem.sizeOfItem(at: destination)) ?? 0
    return PadArchive(id: name, taken: now, padCount: pads.count, byteCount: bytes)
  }

  /// Removes the oldest archives beyond the retention limit.
  @discardableResult
  public func prune(retention: Int) -> [PadArchive] {
    let doomed = ArchivePolicy.pruning(archives(), retention: retention)
    for archive in doomed {
      try? fileSystem.removeItem(at: layout.archiveDirectory(named: archive.id))
    }
    return doomed
  }

  /// Removes every archive. What the settings window's button calls, for a user
  /// who would rather no copies of deleted pads existed at all.
  public func removeAll() {
    for archive in archives() {
      try? fileSystem.removeItem(at: layout.archiveDirectory(named: archive.id))
    }
  }

  /// The archives directory, created if it does not exist yet.
  ///
  /// Exists so that revealing it in Finder does not require the interface to
  /// touch disk, which `CON-4` confines to the store.
  public func directoryForReveal() -> URL {
    try? fileSystem.createDirectory(at: layout.archivesDirectory)
    return layout.archivesDirectory
  }

  /// A summary of what an archive would preserve, used to skip one when nothing
  /// worth keeping has changed (`ArchivePolicy.fingerprint(of:)`).
  ///
  /// Reads each pad's document and metadata, though not its images. That is why
  /// archiving runs after the launch interval closes rather than inside it
  /// (`NFR-1.1`).
  public func fingerprint() -> String {
    let pads =
      (try? fileSystem.contentsOfDirectory(at: layout.padsDirectory))?
      .filter { fileSystem.isDirectory(at: $0) } ?? []
    return ArchivePolicy.fingerprint(of: pads.map(snapshot(of:)))
  }

  private func snapshot(of directory: URL) -> PadSnapshot {
    let content = directory.appendingPathComponent(PadStorageLayout.contentDirectoryName)
    let document =
      (try? fileSystem.contents(of: content.appendingPathComponent(PadContent.documentName)))
      ?? Data()
    let attachments =
      ((try? fileSystem.contentsOfDirectory(at: content)) ?? [])
      .filter { $0.lastPathComponent != PadContent.documentName }
      .reduce(into: [String: Int]()) { result, url in
        result[url.lastPathComponent] = (try? fileSystem.sizeOfItem(at: url)) ?? 0
      }
    return PadSnapshot(
      id: directory.lastPathComponent, document: document, attachments: attachments,
      metadata: metadata(in: directory))
  }

  /// Name, mode and pinning only. Frame and last-opened change when a pad is
  /// moved or opened, and neither is worth a backup.
  private func metadata(in directory: URL) -> PadSnapshot.Metadata {
    let bytes =
      (try? fileSystem.contents(
        of: directory.appendingPathComponent(PadStorageLayout.metadataFileName))) ?? Data()
    guard let decoded = try? PreservingCodec.decode(PadMetadata.self, from: bytes) else {
      return .unreadable(bytes)
    }
    let meta = decoded.value
    return .readable(name: meta.name, mode: meta.mode.rawValue, isPinned: meta.isPinned)
  }
}
