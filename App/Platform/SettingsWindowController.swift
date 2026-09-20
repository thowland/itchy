import AppKit
import SwiftUI

/// Owns the settings window.
///
/// A window of our own rather than SwiftUI's `Settings` scene. From macOS 14 the
/// scene can be opened only by `SettingsLink`; the `showSettingsWindow:` action
/// that used to open it is accepted and then ignored, which is invisible from a
/// menu item and read as the item doing nothing at all. A `MenuBarExtra` in
/// `.menu` style cannot host a `SettingsLink` reliably either, so the scene is
/// not worth keeping.
///
/// The window is created at `.floating` level and brought to the front with the
/// application activated. Pad panels also float, and the application is an
/// accessory, so an ordinary window would open behind both.
@MainActor
final class SettingsWindowController: NSObject, NSWindowDelegate {
  private var window: NSWindow?
  private let coordinator: PadCoordinator

  init(coordinator: PadCoordinator) {
    self.coordinator = coordinator
  }

  var isVisible: Bool { window?.isVisible ?? false }

  /// Opens the window, or brings the open one forward: a second click on the
  /// menu item must not make a second window.
  func show(tab: SettingsTab = .general) {
    let window = existingOrNewWindow(tab: tab)
    self.window = window
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
    window.orderFrontRegardless()
  }

  func close() {
    window?.close()
  }

  func windowWillClose(_ notification: Notification) {
    window = nil
  }

  private func existingOrNewWindow(tab: SettingsTab = .general) -> NSWindow {
    if let window { return window }
    let created = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 620, height: 540),
      styleMask: [.titled, .closable],
      backing: .buffered,
      defer: false)
    created.title = "Itchy Settings"
    created.isReleasedWhenClosed = false
    created.level = .floating
    created.delegate = self
    created.contentView = NSHostingView(
      rootView: SettingsView(initialTab: tab).environment(coordinator))
    created.center()
    return created
  }
}
