import Foundation

/// Creating, renaming, reordering and deleting pads.
extension PadStore {
  // MARK: - Lifecycle

  public func createPad(name: String? = nil) async throws -> PadMetadata {
    guard order.count < limit else { throw PadStoreFault.padLimitReached(limit: limit) }
    let meta = PadMetadata.newPad(name: name ?? Self.defaultName(existing: pads), now: now())
    metadata[meta.id] = meta
    preserved[meta.id] = [:]
    cachedContent[meta.id] = PadContent.empty()
    order.append(meta.id)
    dirty.insert(meta.id)
    try await flush(meta.id)
    try writeIndex()
    continuation.yield(.padAdded(meta.id))
    return meta
  }

  /// A default name, so that creation requires no input from the user
  /// (`FR-2.3`). Names need not be unique (`FR-2.4`), so this is a convenience
  /// rather than an allocation.
  private static func defaultName(existing: [PadMetadata]) -> String {
    let used = Set(existing.map(\.name))
    var candidate = 1
    while used.contains("Pad \(candidate)") {
      candidate += 1
    }
    return "Pad \(candidate)"
  }

  public func deletePad(_ id: PadID) async throws {
    guard metadata[id] != nil || recordedFaults[id] != nil else {
      throw PadStoreFault.unknownPad(id)
    }
    await scheduler.cancel(id)
    try? fileSystem.removeItem(at: layout.directory(for: id))
    metadata[id] = nil
    preserved[id] = nil
    cachedContent[id] = nil
    recordedFaults[id] = nil
    markedOversize.remove(id)
    dirty.remove(id)
    order.removeAll { $0 == id }
    if lastOpened == id { lastOpened = nil }
    try writeIndex()
    continuation.yield(.padRemoved(id))
  }

  public func rename(_ id: PadID, to name: String) async throws {
    try await mutateMetadata(id) { $0.name = name }
  }

  public func setMode(_ id: PadID, to mode: PadMode) async throws {
    try await mutateMetadata(id) { $0.mode = mode }
  }

  public func setPinned(_ id: PadID, _ pinned: Bool) async throws {
    try await mutateMetadata(id) { $0.isPinned = pinned }
  }

  public func setExposedToMCP(_ id: PadID, _ exposed: Bool) async throws {
    try await mutateMetadata(id) { $0.isExposedToMCP = exposed }
  }

  public func setRoutingPolicy(_ id: PadID, _ policy: RoutingPolicy) async throws {
    try await mutateMetadata(id) { $0.routingPolicy = policy }
  }

  /// Nil turns the rule off (`FR-3.8`).
  public func setAccent(_ id: PadID, _ accent: PadAccent?) async throws {
    try await mutateMetadata(id) { $0.accent = accent }
  }

  private func mutateMetadata(
    _ id: PadID,
    _ change: (inout PadMetadata) -> Void
  ) async throws {
    guard var meta = metadata[id] else { throw PadStoreFault.unknownPad(id) }
    change(&meta)
    meta.modified = now()
    metadata[id] = meta
    dirty.insert(id)
    try await flush(id)
    continuation.yield(.metadataChanged(id))
  }

  /// Reordering keeps only pads that exist, and appends any the caller omitted,
  /// so that a stale order from the interface cannot lose a pad.
  public func reorder(to requested: [PadID]) async throws {
    let known = Set(order)
    var result = requested.filter { known.contains($0) }
    let seen = Set(result)
    result.append(contentsOf: order.filter { !seen.contains($0) })
    order = result
    try writeIndex()
    continuation.yield(.padsReordered(order))
  }

  /// `FR-3.4`. Deliberately neither throwing nor part of the content save path:
  /// a frame change does not mark content dirty and does not trigger a content
  /// write (specification §8.4).
  public func setFrame(_ id: PadID, _ frame: PadFrame) async {
    guard metadata[id] != nil else { return }
    metadata[id]?.frame = frame
    dirty.insert(id)
    await scheduler.schedule(id) { [weak self] in
      try? await self?.flush(id)
    }
  }

  public func markOpened(_ id: PadID) async {
    guard metadata[id] != nil else { return }
    metadata[id]?.lastOpened = now()
    lastOpened = id
    dirty.insert(id)
    try? writeIndex()
  }

  /// Lowering the limit below the number of existing pads never deletes or hides
  /// content; it takes effect for creation only (`FR-2.2`).
  public func setPadLimit(_ requested: Int) async {
    limit = PadBounds.clamp(requested)
  }
}
