import AppKit
import ItchyCore
import SwiftUI

/// Application entry point.
///
/// This file is on the coverage exclusion list (Scripts/coverage-exclusions.txt),
/// which means it is subject to the complexity cap in
/// Scripts/swiftlint-excluded.yml and may not branch. Anything resembling a
/// decision belongs in a seam — see specification §15.2.
@main
struct ItchyApp: App {
  @NSApplicationDelegateAdaptor(AppDelegate.self) private var delegate

  var body: some Scene {
    MenuBarExtra("Itchy", systemImage: "cat.fill") {
      MenuContentView()
        .environment(delegate.coordinator)
    }
    .menuBarExtraStyle(.menu)

    Window("Pads", id: WindowIdentifier.pads) {
      PadsWindowView()
        .environment(delegate.coordinator)
    }
    .defaultSize(width: 460, height: 320)

    Settings {
      SettingsView()
        .environment(delegate.coordinator)
    }
  }
}

/// Window identifiers, named once rather than spelled at each call site.
enum WindowIdentifier {
  static let pads = "pads"
}

/// Owns the coordinator and starts it at launch.
///
/// Startup lives here rather than on the menu's `task` modifier because a
/// `MenuBarExtra` in `.menu` style does not instantiate its content until the
/// menu is opened — so a pad list loaded from the menu would not exist until
/// somebody clicked, and nothing else could depend on the store being ready.
@MainActor
final class AppDelegate: NSObject, NSApplicationDelegate {
  let coordinator = AppStorage.makeCoordinator()

  /// `FR-1.1`. `LSUIElement` in Info.plist is the real mechanism; this is belt
  /// and braces for the case of a stale plist in a development build.
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
    Task { await coordinator.start() }
  }

  /// `FR-5.5`: content is force-saved on termination.
  func applicationWillTerminate(_ notification: Notification) {
    coordinator.flushOnTermination()
  }
}
