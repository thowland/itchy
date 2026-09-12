import Foundation

/// A pad panel's position and size, stored against the pad rather than through
/// `setFrameAutosaveName`, so that the frame travels with the pad record and is
/// readable by the same machinery that reads everything else (`FR-3.4`).
public struct PadFrame: Sendable, Codable, Equatable {
  public var x: Double
  public var y: Double
  public var width: Double
  public var height: Double

  /// The display the frame was last recorded on, used by the restoration
  /// heuristics in specification §8.5. Absent when unknown.
  public var displayID: UInt32?

  public init(x: Double, y: Double, width: Double, height: Double, displayID: UInt32? = nil) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.displayID = displayID
  }
}
