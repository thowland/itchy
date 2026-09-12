import SwiftUI

/// Settings window.
///
/// Sprint 0 ships the window and nothing in it. Later sprints extend this rather
/// than restructure it: General in Sprint 4 and 5, Agents in Sprint 8, Models in
/// Sprint 10 (specification §10). Validation and clamping belong in
/// `SettingsModel`, not in this file.
struct SettingsView: View {
  var body: some View {
    TabView {
      Text("Nothing to configure yet.")
        .padding(40)
        .tabItem {
          Label("General", systemImage: "gearshape")
        }
    }
    .frame(width: 460, height: 260)
  }
}
