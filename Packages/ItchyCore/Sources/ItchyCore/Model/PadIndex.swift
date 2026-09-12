import Foundation

/// The top-level index recording slot order (`FR-2.5`, specification §6.2).
///
/// Order is a property of the collection rather than of any pad, so it lives
/// here. When this file is unreadable the index is rebuilt by enumerating the
/// pads directory rather than the application failing to launch (`NFR-2.2`).
public struct PadIndex: Sendable, Codable, Equatable {
  public var schemaVersion: Int
  public var order: [PadID]

  /// The pad the global hotkey opens (`FR-1.4`). Absent before any pad has been
  /// opened.
  public var lastOpened: PadID?

  public init(
    schemaVersion: Int = ItchyCore.schemaVersion,
    order: [PadID] = [],
    lastOpened: PadID? = nil
  ) {
    self.schemaVersion = schemaVersion
    self.order = order
    self.lastOpened = lastOpened
  }

  /// Reconciles the recorded order against the pads actually present.
  ///
  /// Pads named in the index but absent from disk are dropped; pads present but
  /// unnamed are appended in the order given. Both halves matter for `FR-5.8`:
  /// an index that disagrees with the directory must degrade to a usable
  /// application rather than to a crash or a vanished pad.
  public func reconciled(against present: [PadID]) -> PadIndex {
    let presentSet = Set(present)
    var result = order.filter { presentSet.contains($0) }
    let known = Set(result)
    result.append(contentsOf: present.filter { !known.contains($0) })
    var index = self
    index.order = result
    if let last = lastOpened, !presentSet.contains(last) {
      index.lastOpened = nil
    }
    return index
  }
}
