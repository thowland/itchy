import Foundation

/// Whether a pad retains text attributes.
///
/// A per-pad property, never a global setting (`FR-2.8`). Two pads open at once
/// behave according to their own modes.
public enum PadMode: String, Sendable, Codable, CaseIterable {
  /// Retains attributes and inline images.
  case styled
  /// Holds no attributes; pasting inserts text without styling or attachments.
  case plain
}
