import AppKit
import Testing

@testable import Itchy

/// The settings window opened correctly all along — underneath the floating pad
/// panels, where nobody could see it. These cover the parts of putting that
/// right that can be checked without a window server driving the menu.
@MainActor
@Suite("Settings presenter")
struct SettingsPresenterTests {
  private func window(identifier: String?) -> NSWindow {
    let created = NSWindow(
      contentRect: NSRect(x: 0, y: 0, width: 100, height: 100),
      styleMask: [.titled], backing: .buffered, defer: false)
    created.identifier = identifier.map { NSUserInterfaceItemIdentifier(rawValue: $0) }
    return created
  }

  /// By identifier, not by title: the title is the selected tab's name, so it
  /// is "General" until someone clicks "Editor".
  @Test("The settings window is found by identifier")
  func findsByIdentifier() {
    let settings = window(identifier: SettingsPresenter.windowIdentifier)
    let pad = window(identifier: "some-pad")
    let untitled = window(identifier: nil)

    let found = SettingsPresenter.settingsWindow(in: [pad, untitled, settings])

    #expect(found === settings)
  }

  @Test("With no settings window present, nothing is claimed")
  func findsNothing() {
    #expect(SettingsPresenter.settingsWindow(in: [window(identifier: "pad")]) == nil)
    #expect(SettingsPresenter.settingsWindow(in: []) == nil)
  }

  /// macOS 14 renamed the action. Both names are tried so that a rename in
  /// either direction is survivable.
  @Test("Both the current and the former action names are attempted")
  func actionNames() {
    #expect(SettingsPresenter.actionNames.contains("showSettingsWindow:"))
    #expect(SettingsPresenter.actionNames.contains("showPreferencesWindow:"))
    #expect(SettingsPresenter.actionNames.first == "showSettingsWindow:")
  }

  /// The identifier is SwiftUI's, not ours; if it ever changes this is the test
  /// that says so rather than the window silently staying hidden again.
  @Test("The identifier is the one SwiftUI gives its Settings scene")
  func identifier() {
    #expect(SettingsPresenter.windowIdentifier == "com_apple_SwiftUI_Settings_window")
  }
}
