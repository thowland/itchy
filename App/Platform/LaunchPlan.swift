import Foundation
import ItchyCore

/// What happens at launch, and in what order (specification §8.7).
///
/// The budget in `NFR-1.1` is 250 ms from hotkey to a typeable pad, and
/// `FR-1.6` forbids reading pad content at launch. Both are properties of this
/// plan rather than of the code that executes it, so both can be asserted.
struct LaunchPlan: Equatable, Sendable {
  /// Read at launch: a few kilobytes, and what the menubar needs to be live.
  var readsIndexAndMetadata: Bool
  /// `FR-1.6`: never true. Content is read on first open of a pad's panel.
  var readsContentEagerly: Bool
  /// Pinned pads, reopened without taking keyboard focus (`FR-2.7`, D-14).
  var padsToReopen: [PadID]

  static func plan(for pads: [PadMetadata]) -> LaunchPlan {
    LaunchPlan(
      readsIndexAndMetadata: true,
      readsContentEagerly: false,
      padsToReopen: pads.filter(\.isPinned).map(\.id))
  }
}
