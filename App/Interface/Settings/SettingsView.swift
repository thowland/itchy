import ItchyCore
import SwiftUI

/// Settings window.
///
/// Every section the specification's §10 called for is now real: General,
/// Editor, Agents, Models and Backups. Validation and wording live in
/// `SettingsModel`, `MCPSettingsModel` and `ModelSettingsModel`.
struct SettingsView: View {
  @Environment(PadCoordinator.self) private var coordinator

  var body: some View {
    TabView {
      GeneralSettingsView()
        .tabItem { Label("General", systemImage: "gearshape") }
      EditorSettingsView()
        .tabItem { Label("Editor", systemImage: "textformat") }
      AgentSettingsView()
        .tabItem { Label(MCPSettingsModel.sectionTitle, systemImage: "point.3.filled.connected.trianglepath.dotted") }
      ModelSettingsView()
        .tabItem { Label(ModelSettingsModel.sectionTitle, systemImage: "brain") }
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

      DiagnosticLogSection()
    }
    .formStyle(.grouped)
    .padding()
  }
}

/// The diagnostic log. Off by default, and the caption says what it will and
/// will not contain before anyone switches it on.
struct DiagnosticLogSection: View {
  @Environment(PadCoordinator.self) private var coordinator

  var body: some View {
    Section {
      Toggle(
        MCPSettingsModel.loggingLabel,
        isOn: Binding(
          get: { coordinator.settings.debugLoggingEnabled },
          set: { coordinator.setDebugLoggingEnabled($0) })
      )
      .accessibilityIdentifier("settings.debugLogging")

      Text(MCPSettingsModel.loggingCaption(path: coordinator.debugLogPath))
        .font(.caption)
        .foregroundStyle(.secondary)
        .accessibilityIdentifier("settings.debugLoggingCaption")

      Button(MCPSettingsModel.revealLogLabel) {
        coordinator.revealDebugLog()
      }
      .disabled(coordinator.debugLogPath == nil)
    }
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
      Section {
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

      EditorFontSection()
    }
    .formStyle(.grouped)
    .padding()
  }
}

/// The editor font (D-19). Choices and wording are `EditorFontModel`'s; which
/// text the setting reaches is `EditorFontPolicy`'s.
struct EditorFontSection: View {
  @Environment(PadCoordinator.self) private var coordinator

  var body: some View {
    Section {
      Picker(
        "Font",
        selection: Binding(
          get: { coordinator.settings.editorFontFamily },
          set: { coordinator.setEditorFont(family: $0, size: coordinator.settings.editorFontSize) })
      ) {
        Text(EditorFontModel.builtInLabel).tag(String?.none)
        Divider()
        ForEach(
          EditorFontModel.familyChoices(
            available: BodyFont.installedFamilies, current: coordinator.settings.editorFontFamily),
          id: \.self
        ) { family in
          Text(family).tag(String?.some(family))
        }
      }
      .accessibilityIdentifier("settings.editorFont")

      Stepper(
        value: Binding(
          get: { coordinator.settings.editorFontSize },
          set: { coordinator.setEditorFont(family: coordinator.settings.editorFontFamily, size: $0) }),
        in: EditorFontModel.sizeRange,
        step: 1
      ) {
        Text(EditorFontModel.sizeLabel(coordinator.settings.editorFontSize))
      }
      .accessibilityIdentifier("settings.editorFontSize")

      Text(EditorFontModel.sample)
        .font(Font(coordinator.editorFont as CTFont))
        .lineLimit(2)
      Text(EditorFontModel.caption)
        .font(.caption)
        .foregroundStyle(.secondary)
    }
  }
}
