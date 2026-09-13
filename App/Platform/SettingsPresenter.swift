import AppKit

/// Opens the settings window and makes sure it is actually seen.
///
/// Two things go wrong without this, and together they make the menu item look
/// broken. The application is an accessory, so opening a window does not
/// activate it; and pad panels sit at `.floating` level, so an ordinary window
/// opens *underneath* them. The window appears, correctly, somewhere the user
/// cannot see — which reads as the menu item doing nothing at all.
@MainActor
enum SettingsPresenter {
  /// SwiftUI's own identifier for the window its `Settings` scene creates.
  static let windowIdentifier = "com_apple_SwiftUI_Settings_window"

  /// macOS 14 renamed the action behind the Settings menu item. The older name
  /// is tried second so this keeps working if the deployment floor ever moves
  /// back, and so a rename in either direction fails loudly rather than
  /// silently doing nothing.
  static let actionNames = ["showSettingsWindow:", "showPreferencesWindow:"]

  static func show() {
    NSApp.activate(ignoringOtherApps: true)
    sendShowAction()
    // The window is created asynchronously, so it cannot be raised until after
    // the action has been handled.
    DispatchQueue.main.async {
      raiseSettingsWindow()
    }
  }

  private static func sendShowAction() {
    for name in actionNames where NSApp.sendAction(Selector((name)), to: nil, from: nil) {
      return
    }
  }

  /// Lifts the settings window to the same level as the pads, so that a pad
  /// floating above everything does not hide it.
  private static func raiseSettingsWindow() {
    guard let window = settingsWindow(in: NSApp.windows) else { return }
    window.level = .floating
    window.makeKeyAndOrderFront(nil)
    window.center()
  }

  /// Picks the settings window out of the application's windows.
  ///
  /// Matching is by identifier rather than by title, because the title is the
  /// selected tab's name — "General" today, something else after a click.
  static func settingsWindow(in windows: [NSWindow]) -> NSWindow? {
    windows.first { $0.identifier?.rawValue == windowIdentifier }
  }
}
