import Foundation
import ItchyCore

/// What the global hotkey should do (`FR-1.4`, specification §8.6).
///
/// A decision, returned rather than performed, which is the only reason the
/// toggle semantics can be tested at all (D-11). "Already frontmost and focused"
/// is ambiguous for a non-activating panel, so it is stated here precisely and
/// asserted rather than left to the handler.
enum HotKeyAction: Equatable, Sendable {
  /// The target is already frontmost and focused: put it away.
  case close(PadID)
  /// Show it and take keyboard focus.
  case open(PadID)
  /// There are no pads at all.
  case createAndOpen
}

extension HotKeyAction {
  /// The pad the hotkey acts on: the most recently opened, else the first slot.
  static func target(pads: [PadMetadata], lastOpened: PadID?) -> PadID? {
    if let lastOpened, pads.contains(where: { $0.id == lastOpened }) {
      return lastOpened
    }
    return pads.first?.id
  }

  static func decide(
    pads: [PadMetadata],
    lastOpened: PadID?,
    frontmostKeyPad: PadID?
  ) -> HotKeyAction {
    guard let target = target(pads: pads, lastOpened: lastOpened) else {
      return .createAndOpen
    }
    guard frontmostKeyPad == target else {
      return .open(target)
    }
    return .close(target)
  }
}
