import Foundation

/// Reads and writes `endpoint.json` (§11.1).
///
/// Lives under `Store/` because it touches disk, and `CON-4` puts every disk
/// access in one place. That placement is not a formality here: the listener is
/// in the services layer and the settings section is in the app, and neither may
/// open a file, so the file needs an owner in the store or it needs the rule
/// broken.
///
/// Two things follow from writing a port to a file. It is removed on stop, or a
/// stale port outlives the listener and the shim connects to nothing. And it
/// goes through the same atomic write as everything else, because a
/// half-written `endpoint.json` read by a shim starting concurrently is exactly
/// the fault that appears once a month and is never reproduced.
public struct EndpointStore: Sendable {
  private let layout: PadStorageLayout
  private let fileSystem: any FileSystemOperations
  private let atomic: AtomicWrite

  public init(layout: PadStorageLayout, fileSystem: any FileSystemOperations = LocalFileSystem()) {
    self.layout = layout
    self.fileSystem = fileSystem
    self.atomic = AtomicWrite(fileSystem: fileSystem)
  }

  public func write(_ endpoint: MCPEndpoint) throws {
    try fileSystem.createDirectory(at: layout.root)
    try atomic.write(try JSONCoding.encoder().encode(endpoint), to: layout.endpointFile)
  }

  /// Reads the recorded endpoint, or nil when there is none or it is unreadable.
  ///
  /// A file that cannot be decoded is nil rather than an error: to every caller
  /// the answer to "where is the server" is the same in both cases, which is
  /// that there is not one to connect to.
  public func read() -> MCPEndpoint? {
    guard fileSystem.fileExists(at: layout.endpointFile) else { return nil }
    guard let data = try? fileSystem.contents(of: layout.endpointFile) else { return nil }
    return try? JSONCoding.decoder().decode(MCPEndpoint.self, from: data)
  }

  /// Removes the file. Idempotent, because it is called on stop and again at
  /// termination, and a stop that has already happened is not a failure.
  public func clear() {
    guard fileSystem.fileExists(at: layout.endpointFile) else { return }
    try? fileSystem.removeItem(at: layout.endpointFile)
  }
}
