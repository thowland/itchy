import Foundation

/// Reading and staging pad content.
extension PadStore {
  // MARK: - Content

  public func content(of id: PadID) async throws -> PadContent {
    if let cached = cachedContent[id] { return cached }
    guard metadata[id] != nil else { throw PadStoreFault.unknownPad(id) }
    if let fault = recordedFaults[id], fault.prohibitsEditing { throw fault }

    let directory = layout.contentDirectory(for: id)
    guard fileSystem.fileExists(at: directory) else {
      let fault = PadStoreFault.contentMissing(id)
      record(fault, for: id)
      throw fault
    }
    do {
      let bundle = try atomic.readDirectory(at: directory)
      let shadow = layout.shadowFile(for: id)
      let text =
        fileSystem.fileExists(at: shadow)
        ? String(data: try fileSystem.contents(of: shadow), encoding: .utf8) ?? ""
        : ""
      let loaded = PadContent(bundle: bundle, plainText: text)
      cachedContent[id] = loaded
      return loaded
    } catch {
      let fault = PadStoreFault.contentUnreadable(id, underlying: String(describing: error))
      record(fault, for: id)
      throw fault
    }
  }

  public func stage(_ content: PadContent, for id: PadID, origin: WriteOrigin) async {
    guard metadata[id] != nil else { return }
    cachedContent[id] = content
    dirty.insert(id)
    metadata[id]?.modified = now()

    if origin.isExternal {
      metadata[id]?.externalWriteMarker = ExternalWriteMarker(
        at: now(), origin: origin, characterDelta: content.plainText.count)
      continuation.yield(.contentChangedExternally(id, origin: origin))
    }
    noteSizeThreshold(id, bytes: content.byteCount)

    await scheduler.schedule(id) { [weak self] in
      try? await self?.flush(id)
    }
  }

  private func noteSizeThreshold(_ id: PadID, bytes: Int) {
    guard bytes > Self.sizeMarkerThreshold else {
      markedOversize.remove(id)
      return
    }
    guard !markedOversize.contains(id) else { return }
    markedOversize.insert(id)
    continuation.yield(.sizeThresholdCrossed(id, bytes: bytes))
  }
}
