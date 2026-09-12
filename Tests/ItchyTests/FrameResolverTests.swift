import CoreGraphics
import ItchyCore
import Testing

@testable import Itchy

/// `FR-3.4`'s acceptance criterion includes a frame stored for a display that is
/// no longer attached. Testing that by unplugging a monitor is not a test, so the
/// resolver is a pure function over screen rectangles (D-11).
@Suite("Frame resolver")
struct FrameResolverTests {
  private let main = ScreenInfo(
    displayID: 1, visibleFrame: CGRect(x: 0, y: 0, width: 1_920, height: 1_080))
  private let secondary = ScreenInfo(
    displayID: 2, visibleFrame: CGRect(x: 1_920, y: 0, width: 2_560, height: 1_440))

  private func frame(_ x: Double, _ y: Double, _ w: Double = 420, _ h: Double = 520, display: UInt32? = nil)
    -> PadFrame
  {
    PadFrame(x: x, y: y, width: w, height: h, displayID: display)
  }

  @Test("A frame fully on screen is used unchanged")
  func fullyVisible() {
    let stored = frame(100, 100, display: 1)
    let resolved = FrameResolver.resolve(
      stored: stored, screens: [main], mouseScreen: main, openPanelCount: 0)
    #expect(resolved == CGRect(x: 100, y: 100, width: 420, height: 520))
  }

  @Test("A frame mostly offscreen but sufficiently visible is left alone")
  func partiallyVisible() {
    let stored = frame(-280, 100, display: 1)
    let resolved = FrameResolver.resolve(
      stored: stored, screens: [main], mouseScreen: main, openPanelCount: 0)
    #expect(resolved.origin.x == -280, "140pt of it is on screen, which is enough to find")
  }

  @Test("A frame with too little on screen is not used unchanged")
  func barelyVisible() {
    let stored = frame(-400, 100, display: 1)
    let resolved = FrameResolver.resolve(
      stored: stored, screens: [main], mouseScreen: main, openPanelCount: 0)
    #expect(resolved.origin.x != -400)
    #expect(FrameResolver.isSufficientlyVisible(resolved, on: main.visibleFrame))
  }

  /// Rule 2: the display it was on is still attached, so clamp into it.
  @Test("An offscreen frame is clamped into its own display when that display remains")
  func clampedIntoOwnDisplay() {
    let stored = frame(5_000, 5_000, display: 2)
    let resolved = FrameResolver.resolve(
      stored: stored, screens: [main, secondary], mouseScreen: main, openPanelCount: 0)
    #expect(secondary.visibleFrame.contains(resolved))
  }

  /// Rule 3: the display is gone, so place it proportionally rather than
  /// centring it — a pad kept at a corner should stay near that corner.
  @Test("A frame from a detached display lands on an attached one, on screen")
  func detachedDisplay() {
    let stored = frame(3_000, 200, display: 99)
    let resolved = FrameResolver.resolve(
      stored: stored, screens: [main], mouseScreen: main, openPanelCount: 0)
    #expect(FrameResolver.isSufficientlyVisible(resolved, on: main.visibleFrame))
    #expect(resolved.size == CGSize(width: 420, height: 520), "size is preserved")
  }

  @Test("A frame larger than the screen is reduced to fit")
  func oversizedFrame() {
    let stored = frame(0, 0, 4_000, 3_000, display: 99)
    let resolved = FrameResolver.resolve(
      stored: stored, screens: [main], mouseScreen: main, openPanelCount: 0)
    #expect(resolved.width <= main.visibleFrame.width)
    #expect(resolved.height <= main.visibleFrame.height)
  }

  /// Rule 4: no stored frame at all.
  @Test("A pad with no stored frame cascades from the top of the mouse's screen")
  func cascade() {
    let first = FrameResolver.resolve(
      stored: nil, screens: [main], mouseScreen: main, openPanelCount: 0)
    let second = FrameResolver.resolve(
      stored: nil, screens: [main], mouseScreen: main, openPanelCount: 1)
    #expect(first.size == CGSize(width: 420, height: 520))
    #expect(second.origin.x > first.origin.x, "each panel steps right")
    #expect(second.origin.y < first.origin.y, "and down")
    #expect(FrameResolver.isSufficientlyVisible(first, on: main.visibleFrame))
  }

  @Test("Cascading many pads keeps every one of them on screen")
  func cascadeStaysOnScreen() {
    for index in 0..<PadBounds.hardCeiling {
      let resolved = FrameResolver.resolve(
        stored: nil, screens: [main], mouseScreen: main, openPanelCount: index)
      #expect(
        FrameResolver.isSufficientlyVisible(resolved, on: main.visibleFrame),
        "panel \(index) went off screen")
    }
  }

  @Test("With no screens at all the resolver still returns something usable")
  func noScreens() {
    let resolved = FrameResolver.resolve(
      stored: nil, screens: [], mouseScreen: nil, openPanelCount: 0)
    #expect(resolved.size == CGSize(width: 420, height: 520))
  }

  @Test("Visibility needs both dimensions, not just area")
  func visibilityNeedsBothDimensions() {
    let sliver = CGRect(x: -400, y: 100, width: 420, height: 520)
    #expect(!FrameResolver.isSufficientlyVisible(sliver, on: main.visibleFrame))
    let wide = CGRect(x: -300, y: 100, width: 420, height: 520)
    #expect(FrameResolver.isSufficientlyVisible(wide, on: main.visibleFrame))
  }
}
