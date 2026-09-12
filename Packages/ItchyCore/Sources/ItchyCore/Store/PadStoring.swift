import Foundation

/// The store's interface.
///
/// The boundary that matters most in the whole application, because it is what
/// allows a second writer to be added later: the MCP server reads and writes
/// through the same interface a view would use (`CON-4`, specification §5.3).
public protocol PadStoring: Actor {
  var pads: [PadMetadata] { get }
  var faults: [PadID: PadStoreFault] { get }
  var changes: AsyncStream<PadChange> { get }
  var padLimit: Int { get }

  func content(of id: PadID) async throws -> PadContent

  func createPad(name: String?) async throws -> PadMetadata
  func deletePad(_ id: PadID) async throws
  func rename(_ id: PadID, to name: String) async throws
  func setMode(_ id: PadID, to mode: PadMode) async throws
  func reorder(to order: [PadID]) async throws
  func setPinned(_ id: PadID, _ pinned: Bool) async throws
  func setFrame(_ id: PadID, _ frame: PadFrame) async
  func setPadLimit(_ limit: Int) async
  func markOpened(_ id: PadID) async

  /// Records new content in memory, marks the pad dirty, and resets the debounce.
  ///
  /// The hot path. Deliberately neither throwing nor returning a result: the text
  /// view calls this on every change notification and must not be able to block
  /// on I/O or handle an error inline (specification §5.3).
  func stage(_ content: PadContent, for id: PadID, origin: WriteOrigin) async

  func flush(_ id: PadID) async throws
  func flushAll() async throws

  func appendProvenance(_ entry: ProvenanceEntry, to id: PadID) async
  func clearProvenance(of id: PadID) async
}
