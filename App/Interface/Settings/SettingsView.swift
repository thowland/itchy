import ItchyCore
import SwiftUI

/// Settings window.
///
/// Later sprints extend this rather than restructure it: General and Editor are
/// real now, Agents arrives in Sprint 8 and Models in Sprint 10
/// (specification §10). Validation and clamping live in `SettingsModel`.
struct SettingsView: View {
  @Environment(PadCoordinator.self) private var coordinator

  var body: some View {
    TabView {
      GeneralSettingsView()
        .tabItem { Label("General", systemImage: "gearshape") }
      EditorSettingsView()
        .tabItem { Label("Editor", systemImage: "textformat") }
    }
    .environment(coordinator)
    .frame(width: 480, height: 280)
  }
}

struct GeneralSettingsView: View {
  @Environment(PadCoordinator.self) private var coordinator

  var body: some View {
    Form {
      Section {
        Stepper(
          value: Binding(
            get: { coordinator.settings.padLimit },
            set: { coordinator.setPadLimit($0) }),
          in: SettingsModel.padCountRange
        ) {
          Text("Pads: \(coordinator.settings.padLimit)")
        }
        Text(SettingsModel.padCountCaption)
          .font(.caption)
          .foregroundStyle(.secondary)
        LoweringNotice(
          notice: SettingsModel.loweringNotice(
            padCount: coordinator.settings.padLimit, existing: coordinator.pads.count))
      }
    }
    .formStyle(.grouped)
    .padding()
  }
}

/// Shown only when lowering the count below the pads that exist (`FR-2.2`).
struct LoweringNotice: View {
  let notice: String?

  var body: some View {
    Text(notice ?? "")
      .font(.caption)
      .foregroundStyle(.orange)
      .opacity(notice == nil ? 0 : 1)
  }
}

struct EditorSettingsView: View {
  @Environment(PadCoordinator.self) private var coordinator

  var body: some View {
    Form {
      Picker(
        "New pads start as",
        selection: Binding(
          get: { coordinator.settings.defaultMode },
          set: { coordinator.setDefaultMode($0) })
      ) {
        ForEach(PadMode.allCases, id: \.self) { mode in
          Text(SettingsModel.defaultModeLabel(mode)).tag(mode)
        }
      }
      .pickerStyle(.inline)
    }
    .formStyle(.grouped)
    .padding()
  }
}
