import AppKit
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
    MenuBarExtra("Itchy", systemImage: "square.on.square.dashed") {
      MenuContentView()
    }
    .menuBarExtraStyle(.menu)

    Settings {
      SettingsView()
    }
  }
}

/// Asserts the accessory activation policy at launch (FR-1.1).
///
/// `LSUIElement` in Info.plist is the real mechanism; this is belt and braces
/// for the case of a stale plist in a development build.
final class AppDelegate: NSObject, NSApplicationDelegate {
  func applicationDidFinishLaunching(_ notification: Notification) {
    NSApp.setActivationPolicy(.accessory)
  }
}
