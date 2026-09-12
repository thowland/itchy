import Foundation

/// What the store tells its observers.
///
/// Observation flows one way: views observe the store, and a service that needs
/// to affect the interface does so by mutating the store (specification §4).
public enum PadChange: Sendable, Equatable {
  case padsReordered([PadID])
  case padAdded(PadID)
  case padRemoved(PadID)
  case metadataChanged(PadID)

  /// Content was changed by something other than the panel that owns it.
  ///
  /// Deliberately carries no payload: a panel receiving this reloads from the
  /// store, which keeps the reconciliation rules in one place rather than
  /// duplicating them into the event (specification §4).
  case contentChangedExternally(PadID, origin: WriteOrigin)

  case sizeThresholdCrossed(PadID, bytes: Int)
  case storeFault(PadID?, PadStoreFault)
}
