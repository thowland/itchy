import Foundation

/// The store's view of the filesystem.
///
/// A seam, and the only one in the core. It exists because `FR-5.6` and
/// `NFR-2.1` both turn on what happens when a write fails partway through, and
/// the only way to test that honestly is to be able to make a write fail on
/// demand. Tests run against real files in a temporary directory — real
/// filesystem semantics, not a reimplementation of them — with failures injected
/// by decorating this protocol.
public protocol FileSystemOperations: Sendable {
  func fileExists(at url: URL) -> Bool
  func isDirectory(at url: URL) -> Bool
  func contents(of url: URL) throws -> Data
  func write(_ data: Data, to url: URL) throws
  func createDirectory(at url: URL) throws
  func removeItem(at url: URL) throws
  func replaceItem(at destination: URL, with replacement: URL) throws
  func contentsOfDirectory(at url: URL) throws -> [URL]
  func modificationDate(of url: URL) throws -> Date
  func sizeOfItem(at url: URL) throws -> Int

  /// Copies a tree, sharing storage where the filesystem can.
  ///
  /// On APFS this is copy-on-write, so an archive of twenty pads holding
  /// screenshots costs almost no space until one of them is edited. Without it,
  /// ten retained archives of a full store would be measured in gigabytes
  /// (D-18).
  func cloneItem(at source: URL, to destination: URL) throws
}
