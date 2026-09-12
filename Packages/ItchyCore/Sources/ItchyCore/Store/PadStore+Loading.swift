import Foundation

/// Reading the index and pad metadata at launch.
///
/// Content is deliberately not read here (`FR-1.6`): metadata and order are a
/// few kilobytes, and the menubar has to be live inside the budget in `NFR-1.1`.
extension PadStore {
  // MARK: - Loading

  /// Reads the index and every pad's metadata. Does not read any content
  /// (`FR-1.6`): content is read on first open and cached for the process.
  public func load(padLimit requested: Int = PadBounds.defaultCount) async {
    limit = PadBounds.clamp(requested)
    try? fileSystem.createDirectory(at: layout.padsDirectory)
    assertSpotlightExclusion()
    atomic.sweepOrphanedTemporaries(
      in: layout.padsDirectory, olderThan: Self.temporarySweepAge, now: now())

    let present = discoverPads()
    for id in present {
      loadMetadata(id)
      noteMissingContent(id)
    }
    let index = loadIndex().reconciled(against: present.filter { metadata[$0] != nil })
    order = index.order
    lastOpened = index.lastOpened
  }

  /// `NFR-3.4`, D-10: written at first launch and re-asserted on every launch in
  /// case it has been removed.
  private func assertSpotlightExclusion() {
    guard !fileSystem.fileExists(at: layout.spotlightExclusionFile) else { return }
    try? fileSystem.write(Data(), to: layout.spotlightExclusionFile)
  }

  private func discoverPads() -> [PadID] {
    guard let children = try? fileSystem.contentsOfDirectory(at: layout.padsDirectory) else {
      return []
    }
    return
      children
      .filter { fileSystem.isDirectory(at: $0) }
      .compactMap { PadID(string: $0.lastPathComponent) }
      .sorted { $0.rawValue.uuidString < $1.rawValue.uuidString }
  }

  /// An unreadable index is rebuilt by enumeration rather than being allowed to
  /// prevent launch (`NFR-2.2`, specification §6.7).
  private func loadIndex() -> PadIndex {
    guard fileSystem.fileExists(at: layout.indexFile) else { return PadIndex() }
    do {
      let data = try fileSystem.contents(of: layout.indexFile)
      return try JSONCoding.decoder().decode(PadIndex.self, from: data)
    } catch {
      record(.indexUnreadable(underlying: String(describing: error)), for: nil)
      return PadIndex()
    }
  }

  /// Checks that the content directory exists, without reading it.
  ///
  /// `FR-1.6` forbids reading content at launch, and this does not: it is a stat.
  /// The point is that specification §6.7 requires a faulted pad to be *listed*
  /// in a faulted state, which the menubar cannot do if the fault only surfaces
  /// when the pad is opened.
  private func noteMissingContent(_ id: PadID) {
    guard metadata[id] != nil, recordedFaults[id] == nil else { return }
    guard !fileSystem.fileExists(at: layout.contentDirectory(for: id)) else { return }
    record(.contentMissing(id), for: id)
  }

  private func loadMetadata(_ id: PadID) {
    let file = layout.metadataFile(for: id)
    guard fileSystem.fileExists(at: file) else {
      record(.metadataUnreadable(id, underlying: "meta.json is absent"), for: id)
      return
    }
    do {
      let data = try fileSystem.contents(of: file)
      let object = try JSONCoding.decoder().decode([String: JSONValue].self, from: data)
      let (migrated, outcome) = migrator.migrate(object)
      if case .tooNew(let found, let supported) = outcome {
        record(.metadataSchemaTooNew(id, found: found, supported: supported), for: id)
        return
      }
      let migratedData = try JSONCoding.encoder().encode(migrated)
      let decoded = try PreservingCodec.decode(PadMetadata.self, from: migratedData)
      metadata[id] = decoded.value
      preserved[id] = decoded.unknown
    } catch {
      record(.metadataUnreadable(id, underlying: String(describing: error)), for: id)
    }
  }
}
