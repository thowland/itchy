import AppKit
import SwiftUI

/// Menubar contents.
///
/// Sprint 0 ships a static placeholder. Sprint 2 replaces the body with rows
/// projected by `MenuModel` from the store (specification §15.2); the decisions
/// about ordering, size markers and faulted pads live there, not here.
struct MenuContentView: View {
  var body: some View {
    Text("No pads yet")
    Divider()
    SettingsLink {
      Text("Settings…")
    }
    Button("Quit Itchy") {
      NSApplication.shared.terminate(nil)
    }
    .keyboardShortcut("q")
  }
}
