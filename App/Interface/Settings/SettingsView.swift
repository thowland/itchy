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
      ArchiveSettingsView()
        .tabItem { Label("Backups", systemImage: "clock.arrow.circlepath") }
    }
    .environment(coordinator)
    // Tall enough for General with the lowering notice showing; the previous
    // height cut the pad-count section off at the bottom.
    .frame(width: 480, height: 420)
  }
}

struct GeneralSettingsView: View {
  @Environment(PadCoordinator.self) private var coordinator
  @State private var isRecordingHotKey = false

  var body: some View {
    Form {
      Section {
        Toggle(
          "Start Itchy at login",
          isOn: Binding(
            get: { coordinator.settings.launchesAtLogin },
            set: { coordinator.setLaunchesAtLogin($0) }))

        LabeledContent("Global hotkey") {
          HotKeyRecorderView(
            binding: Binding(
              get: { coordinator.hotKeyBinding },
              set: { coordinator.setHotKeyBinding($0) }),
            isRecording: $isRecordingHotKey
          )
          .frame(width: 160, height: 24)
        }
        HotKeyStatus(isRegistered: coordinator.isHotKeyRegistered)
      }

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

/// Says so when the hotkey could not be registered, which usually means another
/// application already holds the combination.
struct HotKeyStatus: View {
  let isRegistered: Bool

  var body: some View {
    Text(HotKeyStatusText.text(isRegistered: isRegistered))
      .font(.caption)
      .foregroundStyle(isRegistered ? AnyShapeStyle(.secondary) : AnyShapeStyle(.orange))
  }
}

/// The wording, out of the view body (D-11).
enum HotKeyStatusText {
  static func text(isRegistered: Bool) -> String {
    isRegistered
      ? "Opens the pad you used last, from anywhere."
      : "This combination is already taken by another application. Try a different one."
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
