import AppKit
import SwiftUI

/// Owns the first-run window.
///
/// A real window brought to the front rather than `runModal`. A blocking modal
/// in an accessory application is a good way to wedge the process with nothing
/// on screen to explain why, and nothing here needs the main thread stopped —
/// the window is the only thing to interact with until it is dismissed.
@MainActor
final class WelcomeWindowController: NSObject, NSWindowDelegate {
  private var window: NSWindow?
  private let onDismiss: () -> Void
  let presentation: WelcomePresentation

  init(presentation: WelcomePresentation = .firstRun, onDismiss: @escaping () -> Void) {
    self.presentation = presentation
    self.onDismiss = onDismiss
  }

  var isVisible: Bool { window?.isVisible ?? false }

  func show() {
    let window = existingOrNewWindow()
    self.window = window
    // Unlike a pad, this one should take focus: it exists because the user
    // cannot otherwise tell the application started (D-14 covers why pads do
    // not).
    NSApp.activate(ignoringOtherApps: true)
    window.center()
    window.makeKeyAndOrderFront(nil)
  }

  func dismiss() {
    window?.close()
  }

  func windowWillClose(_ notification: Notification) {
    window = nil
    onDismiss()
  }

  private func existingOrNewWindow() -> NSWindow {
    if let window { return window }
    let created = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 460, height: 540),
      styleMask: [.titled, .closable, .fullSizeContentView],
      backing: .buffered,
      defer: false)
    created.titlebarAppearsTransparent = true
    created.titleVisibility = .hidden
    created.isMovableByWindowBackground = true
    created.isReleasedWhenClosed = false
    created.level = .floating
    created.delegate = self
    created.contentView = NSHostingView(
      rootView: WelcomeView(
        presentation: presentation, onDismiss: { [weak self] in self?.dismiss() }))
    return created
  }
}
