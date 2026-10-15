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

  /// Whether the panel is rolled up to its title bar (`FR-3.9`, D-34).
  ///
  /// The rectangle above is always the *open* frame, even while this is true:
  /// a shaded panel's own height is a fact about the title bar, not about the
  /// pad, and storing it would lose the size the panel unrolls to.
  public var isShaded: Bool

  public init(
    x: Double, y: Double, width: Double, height: Double,
    displayID: UInt32? = nil, isShaded: Bool = false
  ) {
    self.x = x
    self.y = y
    self.width = width
    self.height = height
    self.displayID = displayID
    self.isShaded = isShaded
  }
}

extension PadFrame {
  private enum CodingKeys: String, CodingKey {
    case x, y, width, height, displayID, isShaded
  }

  /// Written by hand for one field: every `meta.json` from before `FR-3.9` has
  /// no `isShaded`, and its absence means open. A synthesised decoder would
  /// refuse those files rather than read them.
  public init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    x = try container.decode(Double.self, forKey: .x)
    y = try container.decode(Double.self, forKey: .y)
    width = try container.decode(Double.self, forKey: .width)
    height = try container.decode(Double.self, forKey: .height)
    displayID = try container.decodeIfPresent(UInt32.self, forKey: .displayID)
    isShaded = try container.decodeIfPresent(Bool.self, forKey: .isShaded) ?? false
  }
}
