import ItchyCore
import SwiftUI

/// Settings window.
///
/// Every section the specification's §10 called for is now real: General,
/// Editor, Agents, Models and Backups. Validation and wording live in
/// `SettingsModel`, `MCPSettingsModel` and `ModelSettingsModel`.
/// The sections of the settings window, so that it can be opened at one.
///
/// Named rather than positional: the screenshot capture asks for a section by
/// name, and a tab index would move the moment a section is inserted.
enum SettingsTab: String, CaseIterable, Sendable {
  case general
  case editor
  case agents
  case models
  case backups

  /// What an argument or an environment variable can name.
  static func named(_ name: String?) -> SettingsTab {
    guard let name, let tab = SettingsTab(rawValue: name.lowercased()) else { return .general }
    return tab
  }
}

struct SettingsView: View {
  @Environment(PadCoordinator.self) private var coordinator
  @State private var selection: SettingsTab

  init(initialTab: SettingsTab = .general) {
    _selection = State(initialValue: initialTab)
  }

  var body: some View {
    TabView(selection: $selection) {
      GeneralSettingsView()
        .tabItem { Label("General", systemImage: "gearshape") }
        .tag(SettingsTab.general)
      EditorSettingsView()
        .tabItem { Label("Editor", systemImage: "textformat") }
        .tag(SettingsTab.editor)
      AgentSettingsView()
        .tabItem { Label(MCPSettingsModel.sectionTitle, systemImage: "point.3.filled.connected.trianglepath.dotted") }
        .tag(SettingsTab.agents)
      ModelSettingsView()
        .tabItem { Label(ModelSettingsModel.sectionTitle, systemImage: "brain") }
        .tag(SettingsTab.models)
      ArchiveSettingsView()
        .tabItem { Label("Backups", systemImage: "clock.arrow.circlepath") }
        .tag(SettingsTab.backups)
    }
    .environment(coordinator)
    // Wide enough for five tabs. At 480 the fifth did not fit and macOS
    // collapsed the strip into a » overflow button, which hides every section
    // but the first behind a menu nobody looks for — found by screenshotting
    // the window after the Models tab was added.
    .frame(width: 620, height: 540)
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
