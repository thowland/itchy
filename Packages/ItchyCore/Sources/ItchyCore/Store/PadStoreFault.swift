import Foundation

/// Everything that can go wrong in the store.
///
/// `NFR-2.2` requires that a fault affecting one pad does not prevent the
/// application from launching or the other pads from being used, so each case
/// carries enough to report which pad is affected and why. The rule that matters
/// most is stated in specification §6.7: no fault may ever produce an empty
/// editable pad over unreadable content, because that is the one behaviour that
/// would destroy the content on the next save.
public enum PadStoreFault: Error, Sendable, Equatable {
  case metadataUnreadable(PadID, underlying: String)
  case metadataSchemaTooNew(PadID, found: Int, supported: Int)
  case contentUnreadable(PadID, underlying: String)
  case contentMissing(PadID)
  case shadowDesynchronised(PadID)
  case indexUnreadable(underlying: String)
  case writeFailed(PadID?, underlying: String)
  case padLimitReached(limit: Int)
  case diskSpaceExhausted
  case unknownPad(PadID)

  /// The pad this fault concerns, when it concerns one.
  public var padID: PadID? {
    switch self {
    case .metadataUnreadable(let id, _),
      .metadataSchemaTooNew(let id, _, _),
      .contentUnreadable(let id, _),
      .contentMissing(let id),
      .shadowDesynchronised(let id),
      .unknownPad(let id):
      id
    case .writeFailed(let id, _):
      id
    case .indexUnreadable, .padLimitReached, .diskSpaceExhausted:
      nil
    }
  }

  /// Whether the pad is safe to open for editing.
  ///
  /// False means the content could not be read, and the pad must be presented as
  /// faulted rather than as an empty editor (specification §6.7).
  public var prohibitsEditing: Bool {
    switch self {
    case .metadataUnreadable, .metadataSchemaTooNew, .contentUnreadable, .contentMissing:
      true
    case .shadowDesynchronised, .indexUnreadable, .writeFailed,
      .padLimitReached, .diskSpaceExhausted, .unknownPad:
      false
    }
  }

  public var reason: String {
    switch self {
    case .metadataUnreadable(let id, let underlying):
      "metadata for \(id) is unreadable: \(underlying)"
    case .metadataSchemaTooNew(let id, let found, let supported):
      "metadata for \(id) is schema version \(found); this build supports \(supported)"
    case .contentUnreadable(let id, let underlying):
      "content for \(id) is unreadable: \(underlying)"
    case .contentMissing(let id):
      "content for \(id) is missing"
    case .shadowDesynchronised(let id):
      "shadow text for \(id) disagrees with its content"
    case .indexUnreadable(let underlying):
      "the pad index is unreadable: \(underlying)"
    case .writeFailed(let id, let underlying):
      "write failed\(id.map { " for \($0)" } ?? ""): \(underlying)"
    case .padLimitReached(let limit):
      "the pad limit of \(limit) has been reached"
    case .diskSpaceExhausted:
      "there is not enough disk space to save"
    case .unknownPad(let id):
      "no such pad: \(id)"
    }
  }
}
