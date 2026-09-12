import CoreGraphics
import Foundation
import ItchyCore

/// What is on the pasteboard, reduced to what the decision needs.
///
/// The interceptor reads the pasteboard into this; everything after is a pure
/// decision (D-11, specification §15.2).
struct PasteDescriptor: Equatable, Sendable {
  var hasRTFD: Bool = false
  var hasRTF: Bool = false
  var hasHTML: Bool = false
  var imageSizes: [CGSize] = []
  var plainText: String?
  var url: URL?
  var fileURLs: [URL] = []
  var sourceBundleID: String?
  var sourceAppName: String?
  var byteCount: Int = 0
}

/// Which representation is taken from the pasteboard.
enum PasteRepresentation: String, Equatable, Sendable {
  case rtfd
  case rtf
  case html
  case image
  case plainText
  case nothing
}

/// The decision about one paste or drop (specification §9.4).
struct PastePlan: Equatable, Sendable {
  var representation: PasteRepresentation
  /// One entry per image on the pasteboard: the size to resample to, or nil to
  /// take it as it is.
  var downsampleTargets: [CGSize?]
  /// Plain mode holds no attributes and no attachments (`FR-4.4`).
  var discardsStyling: Bool
  var provenanceKind: ProvenanceEntry.Kind?

  /// Nothing usable was on the pasteboard.
  static let empty = PastePlan(
    representation: .nothing, downsampleTargets: [], discardsStyling: false,
    provenanceKind: nil)

  static func plan(for descriptor: PasteDescriptor, mode: PadMode) -> PastePlan {
    let representation = chooseRepresentation(descriptor, mode: mode)
    guard representation != .nothing else { return .empty }

    let targets =
      representation == .image
      ? descriptor.imageSizes.map(DownsamplePolicy.target(for:))
      : []

    return PastePlan(
      representation: representation,
      downsampleTargets: targets,
      discardsStyling: mode == .plain,
      provenanceKind: provenanceKind(for: representation, descriptor: descriptor))
  }

  /// Plain mode reduces everything to text; styled mode prefers the richest
  /// representation available (specification §9.4, steps 3 and 4).
  private static func chooseRepresentation(
    _ descriptor: PasteDescriptor,
    mode: PadMode
  ) -> PasteRepresentation {
    guard mode == .styled else {
      return descriptor.plainText?.isEmpty == false ? .plainText : .nothing
    }
    if descriptor.hasRTFD { return .rtfd }
    if descriptor.hasRTF { return .rtf }
    if descriptor.hasHTML { return .html }
    if !descriptor.imageSizes.isEmpty { return .image }
    if descriptor.plainText?.isEmpty == false { return .plainText }
    return .nothing
  }

  private static func provenanceKind(
    for representation: PasteRepresentation,
    descriptor: PasteDescriptor
  ) -> ProvenanceEntry.Kind? {
    if !descriptor.fileURLs.isEmpty { return .file }
    switch representation {
    case .image: return .image
    case .rtfd, .rtf, .html: return .styledText
    case .plainText: return .text
    case .nothing: return nil
    }
  }
}

/// Builds the provenance entry for a paste (`FR-7.1`).
///
/// Written in Sprint 3 alongside the interceptor even though provenance itself
/// is R2, because retrofitting it later means revisiting this same code and
/// re-deriving the capture ordering in §9.5.
enum ProvenanceBuilder {
  static func entry(
    from descriptor: PasteDescriptor,
    plan: PastePlan,
    insertedAt location: Int,
    length: Int,
    now: Date
  ) -> ProvenanceEntry? {
    guard let kind = plan.provenanceKind else { return nil }
    return ProvenanceEntry(
      arrived: now,
      sourceBundleID: descriptor.sourceBundleID,
      sourceAppName: descriptor.sourceAppName,
      sourceURL: descriptor.url ?? descriptor.fileURLs.first,
      approximateRange: location..<(location + length),
      byteCount: descriptor.byteCount,
      kind: kind)
  }
}
