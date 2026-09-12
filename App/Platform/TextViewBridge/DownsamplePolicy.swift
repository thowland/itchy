import CoreGraphics
import Foundation

/// Decides whether a pasted image is too large and what to reduce it to
/// (`FR-4.3`, specification §9.4).
///
/// A pure decision so that the threshold can be tested either side without
/// pasting anything. The resampling itself is performed by the interceptor.
enum DownsamplePolicy {
  /// Longest edge, in pixels.
  ///
  /// Chosen to reduce an ordinary Retina screenshot substantially while leaving
  /// a screenshot of text legible. `NFR-1.4`'s budget follows from it: twenty
  /// full-screen Retina pastes land around 20–40 MB, so the documented per-pad
  /// ceiling is 64 MB and the size marker appears at 32 MB.
  static let maximumEdge: CGFloat = 1_600

  /// The size to resample to, or nil when the image is already small enough.
  static func target(for size: CGSize) -> CGSize? {
    let longest = max(size.width, size.height)
    guard longest > maximumEdge, longest > 0 else { return nil }
    let scale = maximumEdge / longest
    return CGSize(
      width: (size.width * scale).rounded(),
      height: (size.height * scale).rounded())
  }
}
