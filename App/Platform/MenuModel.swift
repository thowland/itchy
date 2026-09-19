import Foundation
import ItchyCore

/// One row in the menubar.
struct MenuRow: Equatable, Identifiable, Sendable {
  let id: PadID
  /// One-based slot position, as shown to the user.
  let slot: Int
  let name: String
  let mode: PadMode
  let isPinned: Bool
  /// A pad whose content could not be read. Selectable, but it opens onto the
  /// fault rather than onto an editor (specification §6.7).
  let isFaulted: Bool
  /// Present once the pad passes the size threshold (`FR-5.9`).
  let sizeMarker: String?
  /// `1`…`9` for the first nine pads; nil beyond that.
  let keyEquivalent: String?
  /// Something outside the application wrote to this pad and the person has not
  /// opened it since (`FR-8.9`, §11.7). The compensating control for D-9's
  /// consequence that a write to a closed pad has no undo: the menu is where
  /// they will next look at the pad, so the menu is where it must say so.
  let hasUnseenExternalWrite: Bool
}

/// Projects store state into menubar rows.
///
/// Everything the menu decides lives here rather than in the view: ordering,
/// slot numbers, size markers, faulted presentation and key equivalents (D-11,
/// specification §15.2). `MenuContentView` renders these and nothing else.
enum MenuModel {
  /// Beyond nine, a key equivalent would need a modifier the menu does not own.
  static let keyEquivalentLimit = 9

  static func rows(
    pads: [PadMetadata],
    faults: [PadID: PadStoreFault] = [:],
    sizes: [PadID: Int] = [:],
    threshold: Int = PadStore.sizeMarkerThreshold,
    openPads: Set<PadID> = []
  ) -> [MenuRow] {
    pads.enumerated().map { index, pad in
      let bytes = sizes[pad.id] ?? 0
      return MenuRow(
        id: pad.id,
        slot: index + 1,
        name: pad.name,
        mode: pad.mode,
        isPinned: pad.isPinned,
        isFaulted: faults[pad.id]?.prohibitsEditing ?? false,
        sizeMarker: bytes > threshold ? sizeLabel(bytes) : nil,
        keyEquivalent: index < keyEquivalentLimit ? String(index + 1) : nil,
        // An open pad shows the banner instead; the menu marker is for the pad
        // the person has not looked at.
        hasUnseenExternalWrite: pad.externalWriteMarker != nil && !openPads.contains(pad.id))
    }
  }

  /// What the user reads when a pad has grown past the threshold.
  ///
  /// Deliberately coarse: the number exists to make growth noticeable, not to be
  /// accurate to the byte.
  static func sizeLabel(_ bytes: Int) -> String {
    let megabytes = Double(bytes) / 1_048_576
    if megabytes >= 1000 {
      return String(format: "%.1f GB", megabytes / 1024)
    }
    return "\(Int(megabytes.rounded())) MB"
  }

  /// What the menu shows when there are no pads at all.
  static let emptyTitle = "No pads yet"

  /// What the menubar says about the agent server, or nothing when it is off
  /// (`FR-8.10`, §11.8).
  ///
  /// A row rather than a branch in the view, for the same reason as every other
  /// row here: the menu renders what this decides. Off produces no row at all —
  /// the requirement is that the state is visible when there is a state, not
  /// that a line of the menu is permanently spent saying "no".
  static func serverRow(_ state: MCPServerState) -> String? {
    switch state {
    case .off: nil
    case .starting: "Agents: starting…"
    case .listening(let port): "Agents: listening on \(port)"
    case .failed: "Agents: could not start"
    }
  }
}
