import Foundation

/// Records that a pad was written by something other than the user (`FR-8.9`).
///
/// Set on every non-user write. When the panel is open a banner appears; when it
/// is closed the marker persists so that the user learns about the write on next
/// open, which is the compensating control for D-9's consequence that a write to
/// a closed pad has no undo.
public struct ExternalWriteMarker: Sendable, Codable, Equatable {
  public let at: Date
  public let origin: WriteOrigin
  public let characterDelta: Int

  public init(at: Date, origin: WriteOrigin, characterDelta: Int) {
    self.at = at
    self.origin = origin
    self.characterDelta = characterDelta
  }
}
