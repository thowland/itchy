import AppKit
import CoreGraphics

/// Reads the current screen layout into the plain values `FrameResolver` works
/// with, so that the resolver itself needs no AppKit and can be tested without a
/// window server (D-11).
enum ScreenReader {
  static func displayID(of screen: NSScreen) -> UInt32? {
    screen.deviceDescription[NSDeviceDescriptionKey("NSScreenNumber")] as? UInt32
  }

  static func screens(_ screens: [NSScreen] = NSScreen.screens) -> [ScreenInfo] {
    screens.compactMap { screen in
      guard let identifier = displayID(of: screen) else { return nil }
      return ScreenInfo(displayID: identifier, visibleFrame: screen.visibleFrame)
    }
  }

  /// The screen the pointer is on, which is where a pad with no stored frame
  /// should appear.
  static func mouseScreen(_ screens: [NSScreen] = NSScreen.screens) -> ScreenInfo? {
    let location = NSEvent.mouseLocation
    let found = screens.first { $0.frame.contains(location) } ?? screens.first
    guard let found, let identifier = displayID(of: found) else { return nil }
    return ScreenInfo(displayID: identifier, visibleFrame: found.visibleFrame)
  }
}
