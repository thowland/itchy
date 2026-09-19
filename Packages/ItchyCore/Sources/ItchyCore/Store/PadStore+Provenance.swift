import Foundation

/// Provenance, stored in metadata rather than in text attributes so that it
/// survives a flatten (`FR-7.2`).
extension PadStore {
  // MARK: - Provenance

  public func appendProvenance(_ entry: ProvenanceEntry, to id: PadID) async {
    guard var pad = metadata[id] else { return }
    pad.provenance = ProvenanceBounds.trimmed(pad.provenance + [entry])
    metadata[id] = pad
    dirty.insert(id)
    await scheduler.schedule(id) { [weak self] in
      try? await self?.flush(id)
    }
  }

  public func clearProvenance(of id: PadID) async {
    guard metadata[id] != nil else { return }
    metadata[id]?.provenance.removeAll()
    dirty.insert(id)
    await scheduler.schedule(id) { [weak self] in
      try? await self?.flush(id)
    }
  }

  public func clearExternalWriteMarker(of id: PadID) async {
    guard metadata[id] != nil else { return }
    metadata[id]?.externalWriteMarker = nil
    dirty.insert(id)
  }
}
