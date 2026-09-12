import Foundation

/// Getting bytes onto disk.
///
/// Content, then shadow, then metadata — metadata last because `modified` is the
/// thing that claims the save happened (specification §6.3).
extension PadStore {
  // MARK: - Writing

  /// Writes content, then shadow, then metadata.
  ///
  /// Metadata is written last because `modified` is the thing that claims the
  /// save happened, and a metadata write landing without its content would be
  /// the one genuinely misleading outcome (specification §6.3).
  public func flush(_ id: PadID) async throws {
    await scheduler.cancel(id)
    guard let meta = metadata[id] else { throw PadStoreFault.unknownPad(id) }
    guard dirty.contains(id) || !fileSystem.fileExists(at: layout.metadataFile(for: id)) else {
      return
    }
    let content = cachedContent[id] ?? PadContent.empty()
    do {
      try fileSystem.createDirectory(at: layout.directory(for: id))
      try atomic.writeDirectory(content.bundle, to: layout.contentDirectory(for: id))
      try atomic.write(Data(content.plainText.utf8), to: layout.shadowFile(for: id))
      let data = try PreservingCodec.encode(meta, preserving: preserved[id] ?? [:])
      try atomic.write(data, to: layout.metadataFile(for: id))
      dirty.remove(id)
    } catch {
      let fault = Self.classify(error, for: id)
      record(fault, for: id)
      throw fault
    }
  }

  public func flushAll() async throws {
    var firstError: (any Error)?
    for id in order where dirty.contains(id) {
      do {
        try await flush(id)
      } catch {
        firstError = firstError ?? error
      }
    }
    try writeIndex()
    if let error = firstError { throw error }
  }

  internal func writeIndex() throws {
    let index = PadIndex(order: order, lastOpened: lastOpened)
    do {
      let data = try JSONCoding.encoder().encode(index)
      try atomic.write(data, to: layout.indexFile)
    } catch {
      let fault = Self.classify(error, for: nil)
      record(fault, for: nil)
      throw fault
    }
  }

  /// Disk-full is distinguished from an ordinary write failure because the
  /// remedy is different and the user can act on it.
  private static func classify(_ error: any Error, for id: PadID?) -> PadStoreFault {
    if let fault = error as? PadStoreFault { return fault }
    let code = (error as NSError).code
    if code == NSFileWriteOutOfSpaceError || code == Int(ENOSPC) {
      return .diskSpaceExhausted
    }
    return .writeFailed(id, underlying: String(describing: error))
  }
}
