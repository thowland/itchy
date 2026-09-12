import Foundation
import ItchyCore

/// Damages a store on purpose, so that each fault can be looked at rather than
/// only asserted (specification §6.7).
struct FaultInjection {
  let layout: PadStorageLayout
  let pad: PadID

  func corruptMetadata() throws {
    try write(Data("{ this is not json".utf8), to: layout.metadataFile(for: pad))
  }

  func futureSchema() throws {
    let file = layout.metadataFile(for: pad)
    var object = try JSONCoding.decoder().decode([String: JSONValue].self, from: try read(file))
    object["schemaVersion"] = .number(99)
    try write(try JSONCoding.encoder().encode(object), to: file)
  }

  func removeContent() throws {
    try remove(layout.contentDirectory(for: pad))
  }

  func corruptIndex() throws {
    try write(Data("not an index".utf8), to: layout.indexFile)
  }

  // The harness is outside the store, so it reaches disk through the store's own
  // filesystem type rather than FileManager (CON-4).
  private let fileSystem = LocalFileSystem()
  private func write(_ data: Data, to url: URL) throws { try fileSystem.write(data, to: url) }
  private func read(_ url: URL) throws -> Data { try fileSystem.contents(of: url) }
  private func remove(_ url: URL) throws { try fileSystem.removeItem(at: url) }
}
