import AppKit
import Foundation
import ItchyCore
import Testing

@testable import Itchy

/// The menu item used to send `showSettingsWindow:`, which macOS 14 accepts and
/// ignores unless it comes from a `SettingsLink` — so no window ever appeared.
/// These replace the tests for that presenter, which checked the action names
/// and SwiftUI's window identifier rather than whether anything opened.
@MainActor
@Suite("Settings window")
struct SettingsWindowTests {
  private func makeCoordinator() -> (PadCoordinator, URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-settings-\(UUID().uuidString)")
    let layout = PadStorageLayout(root: root)
    let coordinator = PadCoordinator(
      store: PadStore(layout: layout), layout: layout, launchOptions: LaunchOptions())
    return (coordinator, root)
  }

  @Test("Showing settings opens a window above the floating pads")
  func opensAboveThePads() {
    let (coordinator, root) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }

    coordinator.showSettings()
    defer { coordinator.closeSettings() }

    #expect(coordinator.isShowingSettings)
    let window = NSApp.windows.first { $0.delegate is SettingsWindowController }
    #expect(window?.level == .floating, "pads float; an ordinary window opens behind them")
  }

  @Test("A second request reuses the open window")
  func reusesTheWindow() {
    let (coordinator, root) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }

    coordinator.showSettings()
    coordinator.showSettings()
    defer { coordinator.closeSettings() }

    let count = NSApp.windows.filter { $0.delegate is SettingsWindowController && $0.isVisible }
      .count
    #expect(count == 1)
  }

  @Test("Closing it can be followed by opening it again")
  func reopensAfterClosing() async {
    let (coordinator, root) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }

    coordinator.showSettings()
    coordinator.closeSettings()
    await expect("the window to close") { !coordinator.isShowingSettings }

    coordinator.showSettings()
    defer { coordinator.closeSettings() }
    #expect(coordinator.isShowingSettings)
  }
}
