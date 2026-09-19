import AppKit
import SwiftUI

/// Owns the help window.
///
/// The same shape as `WelcomeWindowController` and for the same reasons: a real
/// window rather than a modal, because a blocking modal in an accessory
/// application is a good way to wedge the process with nothing on screen to
/// explain why.
///
/// Unlike a pad, this window takes focus. A pad appearing must not activate the
/// application (D-14); help that appeared behind the thing you were confused by
/// would be no help.
@MainActor
final class HelpWindowController: NSObject, NSWindowDelegate {
  private var window: NSWindow?
  private let onClose: () -> Void
  private(set) var topic: String

  init(topic: String = HelpBook.defaultTopic, onClose: @escaping () -> Void) {
    self.topic = topic
    self.onClose = onClose
  }

  var isVisible: Bool { window?.isVisible ?? false }

  func show() {
    let window = existingOrNewWindow()
    self.window = window
    NSApp.activate(ignoringOtherApps: true)
    window.makeKeyAndOrderFront(nil)
  }

  func close() {
    window?.close()
  }

  func windowWillClose(_ notification: Notification) {
    window = nil
    onClose()
  }

  private func existingOrNewWindow() -> NSWindow {
    if let window { return window }
    let created = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 760, height: 540),
      styleMask: [.titled, .closable, .miniaturizable, .resizable],
      backing: .buffered,
      defer: false)
    created.title = HelpText.windowTitle
    created.isReleasedWhenClosed = false
    created.delegate = self
    created.center()
    created.contentView = NSHostingView(rootView: HelpView(topic: topic))
    return created
  }
}

/// Wording for the ways in, out of the views that offer them.
enum HelpText {
  static let windowTitle = "Itchy Help"
  /// What the menubar entry says. "Itchy Help" rather than "Help", because in a
  /// menu that also lists pads a bare "Help" reads like one.
  static let menuTitle = "Itchy Help"
  /// On the About screen, beside the dismiss button.
  static let aboutButton = "Help"
}
