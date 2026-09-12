import Foundation
import ItchyCore

/// How a pad whose content could not be read is presented (specification §6.7).
///
/// The rule this exists to enforce: a faulted pad is listed, selectable, and
/// opens onto the fault — never onto an empty editor. An empty editor over
/// unreadable content is the one behaviour that would destroy that content on the
/// next save, so it is prohibited rather than discouraged.
enum FaultPresentation {
  struct Presentation: Equatable, Sendable {
    /// False means show the fault, not an editor.
    let allowsEditing: Bool
    let headline: String
    let detail: String
    /// Offered so the user can look at what is actually on disk.
    let offersRevealInFinder: Bool
  }

  static func presentation(for fault: PadStoreFault?) -> Presentation? {
    guard let fault else { return nil }
    return Presentation(
      allowsEditing: !fault.prohibitsEditing,
      headline: headline(for: fault),
      detail: fault.reason,
      offersRevealInFinder: fault.prohibitsEditing)
  }

  /// Whether the editor may be shown at all.
  static func allowsEditing(_ fault: PadStoreFault?) -> Bool {
    guard let fault else { return true }
    return !fault.prohibitsEditing
  }

  /// Split along the same line as `prohibitsEditing`, which is the distinction
  /// that matters: faults about this pad's readable content, and everything
  /// else. One ten-case switch would read as a lookup table anyway.
  private static func headline(for fault: PadStoreFault) -> String {
    contentHeadline(for: fault) ?? storeHeadline(for: fault)
  }

  /// Faults about this pad's own content. These prohibit editing.
  private static func contentHeadline(for fault: PadStoreFault) -> String? {
    switch fault {
    case .contentMissing:
      "This pad's content is missing"
    case .contentUnreadable:
      "This pad's content could not be read"
    case .metadataUnreadable:
      "This pad's record could not be read"
    case .metadataSchemaTooNew:
      "This pad was written by a newer version of Itchy"
    default:
      nil
    }
  }

  /// Everything else: the pad is still editable, but something is wrong.
  private static func storeHeadline(for fault: PadStoreFault) -> String {
    switch fault {
    case .shadowDesynchronised:
      "This pad's plain-text copy is out of date"
    case .indexUnreadable:
      "The pad list could not be read"
    case .writeFailed:
      "The last save did not complete"
    case .padLimitReached:
      "No free pad slots"
    case .diskSpaceExhausted:
      "There is not enough disk space to save"
    default:
      "This pad no longer exists"
    }
  }
}
