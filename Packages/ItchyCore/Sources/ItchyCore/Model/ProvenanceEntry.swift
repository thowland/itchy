import Foundation

/// A note of where a piece of pasted or dropped content came from (`FR-7.1`).
///
/// Stored in metadata rather than as a text attribute, because attributes are
/// exactly what flattening destroys and provenance must outlive that operation
/// (`FR-7.2`).
public struct ProvenanceEntry: Sendable, Codable, Equatable, Identifiable {
  /// What kind of content arrived.
  public enum Kind: String, Sendable, Codable, CaseIterable {
    case text
    case styledText
    case image
    case file
  }

  public let id: UUID
  public let arrived: Date
  public let sourceBundleID: String?
  public let sourceAppName: String?
  public let sourceURL: URL?

  /// The range the content occupied at the moment it was inserted.
  ///
  /// Approximate by construction and never authoritative (`FR-7.4`): ranges
  /// drift as the user edits, and maintaining accurate mapping through arbitrary
  /// editing is more machinery than this feature is worth.
  public let approximateRange: Range<Int>?

  public let byteCount: Int
  public let kind: Kind

  public init(
    id: UUID = UUID(),
    arrived: Date,
    sourceBundleID: String? = nil,
    sourceAppName: String? = nil,
    sourceURL: URL? = nil,
    approximateRange: Range<Int>? = nil,
    byteCount: Int,
    kind: Kind
  ) {
    self.id = id
    self.arrived = arrived
    self.sourceBundleID = sourceBundleID
    self.sourceAppName = sourceAppName
    self.sourceURL = sourceURL
    self.approximateRange = approximateRange
    self.byteCount = byteCount
    self.kind = kind
  }
}
