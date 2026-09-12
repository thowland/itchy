import CoreGraphics
import Foundation
import ItchyCore

/// A screen, reduced to what frame restoration needs.
struct ScreenInfo: Equatable, Sendable {
  let displayID: UInt32
  /// The area excluding the menubar and Dock.
  let visibleFrame: CGRect
}

/// Decides where a pad panel opens (`FR-3.4`, specification §8.5).
///
/// A pure function over a stored frame and a set of screen rectangles, so that
/// the interesting cases — a display that is no longer attached, a frame mostly
/// offscreen — are tested by calling it rather than by unplugging a monitor.
enum FrameResolver {
  /// How much of the stored frame must be on some screen for it to be used
  /// unchanged. Smaller than this and the panel is effectively lost.
  static let minimumVisible = CGSize(width: 120, height: 80)

  /// Each additional open panel is offset by this much, so that opening several
  /// pads does not stack them exactly.
  static let cascadeStep: CGFloat = 28

  static func resolve(
    stored: PadFrame?,
    screens: [ScreenInfo],
    mouseScreen: ScreenInfo?,
    openPanelCount: Int
  ) -> CGRect {
    let fallbackScreen = mouseScreen ?? screens.first
    guard let stored else {
      return cascaded(on: fallbackScreen, index: openPanelCount)
    }
    let frame = CGRect(x: stored.x, y: stored.y, width: stored.width, height: stored.height)

    // 1. Enough of it is on some screen: use it unchanged.
    //
    // Except that "unchanged" cannot mean larger than the screen it is on.
    // Specification §8.5 rule 1 does not say so, because the case it has in mind
    // is a frame that has drifted rather than one recorded on a much larger
    // display — but a panel wider than the display has its controls off the edge
    // and is unusable, so the size is clamped even when the position is kept.
    if let screen = screens.first(where: { isSufficientlyVisible(frame, on: $0.visibleFrame) }) {
      guard fits(frame, in: screen.visibleFrame) else {
        return clamp(frame, into: screen.visibleFrame)
      }
      return frame
    }
    // 2. Its own display is still attached: clamp into it.
    let ownScreen = stored.displayID.flatMap { identifier in
      screens.first { $0.displayID == identifier }
    }
    if let ownScreen {
      return clamp(frame, into: ownScreen.visibleFrame)
    }
    // 3. Otherwise place it proportionally on the fallback screen.
    //
    // Proportional rather than centred: a user who keeps a pad at the bottom
    // right of a large display finds it bottom right on the laptop screen too,
    // which is what they meant by putting it there.
    guard let fallbackScreen else { return frame }
    return proportional(frame, from: stored, onto: fallbackScreen.visibleFrame)
  }

  static func fits(_ frame: CGRect, in visible: CGRect) -> Bool {
    frame.width <= visible.width && frame.height <= visible.height
  }

  static func isSufficientlyVisible(_ frame: CGRect, on visible: CGRect) -> Bool {
    let overlap = frame.intersection(visible)
    guard !overlap.isNull else { return false }
    return overlap.width >= minimumVisible.width && overlap.height >= minimumVisible.height
  }

  static func clamp(_ frame: CGRect, into visible: CGRect) -> CGRect {
    let size = CGSize(
      width: min(frame.width, visible.width),
      height: min(frame.height, visible.height))
    let x = min(max(frame.minX, visible.minX), visible.maxX - size.width)
    let y = min(max(frame.minY, visible.minY), visible.maxY - size.height)
    return CGRect(x: x, y: y, width: size.width, height: size.height)
  }

  /// Places the frame at the same proportional offset within the new screen as
  /// it had within the one it was recorded on.
  ///
  /// The originating screen's bounds are unknown once it is detached, so the
  /// stored frame's own position is used as the reference: what is preserved is
  /// which corner the pad was nearest.
  static func proportional(_ frame: CGRect, from stored: PadFrame, onto visible: CGRect) -> CGRect {
    let size = CGSize(
      width: min(frame.width, visible.width),
      height: min(frame.height, visible.height))
    let reference = CGRect(
      x: stored.x, y: stored.y, width: stored.width, height: stored.height)
    let span = max(reference.width, 1)
    let horizontal = reference.minX < 0 ? 0 : min(reference.minX / max(span * 4, 1), 1)
    let vertical = reference.minY < 0 ? 0 : min(reference.minY / max(reference.height * 4, 1), 1)
    return CGRect(
      x: visible.minX + (visible.width - size.width) * horizontal,
      y: visible.minY + (visible.height - size.height) * vertical,
      width: size.width,
      height: size.height)
  }

  /// Top-left of the screen, stepped down and right by the number already open.
  static func cascaded(on screen: ScreenInfo?, index: Int) -> CGRect {
    let size = PanelDefaults.size
    guard let screen else {
      return CGRect(origin: .zero, size: size)
    }
    let visible = screen.visibleFrame
    let step = cascadeStep * CGFloat(index)
    let x = min(visible.minX + 24 + step, visible.maxX - size.width)
    let y = max(visible.maxY - size.height - 24 - step, visible.minY)
    return CGRect(x: x, y: y, width: size.width, height: size.height)
  }
}

/// Default panel geometry, kept out of `PanelConfiguration` so that
/// `FrameResolver` does not need AppKit.
enum PanelDefaults {
  static let size = CGSize(width: 420, height: 520)
}
