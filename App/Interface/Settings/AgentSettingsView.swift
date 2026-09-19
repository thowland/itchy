import ItchyCore
import SwiftUI

/// The Agents section (`FR-8.4`, `FR-8.10`, specification §10).
///
/// On the coverage exclusion list, so it may not branch. Every string, every
/// range and every judgement about whether the server's state reads as a
/// problem is `MCPSettingsModel`'s; this shows them and calls the coordinator.
struct AgentSettingsView: View {
  @Environment(PadCoordinator.self) private var coordinator
  @State private var isTokenRevealed = false

  var body: some View {
    Form {
      Section {
        Toggle(
          MCPSettingsModel.enableLabel,
          isOn: Binding(
            get: { coordinator.settings.mcpServerEnabled },
            set: { coordinator.setMCPEnabled($0) })
        )
        .accessibilityIdentifier("settings.mcpEnabled")

        ServerStatusText(state: coordinator.serverState)

        Stepper(
          value: Binding(
            get: { coordinator.settings.mcpPort },
            set: { coordinator.setMCPPort($0) }),
          in: MCPSettingsModel.portRange
        ) {
          Text("\(MCPSettingsModel.portLabel): \(String(coordinator.settings.mcpPort))")
        }
        .accessibilityIdentifier("settings.mcpPort")

        ServerPortNote(
          note: MCPSettingsModel.portNote(
            configured: coordinator.settings.mcpPort, state: coordinator.serverState))
      }

      Section {
        LabeledContent(MCPSettingsModel.tokenLabel) {
          Text(
            MCPSettingsModel.tokenDisplay(
              coordinator.mcpToken?.value, revealed: isTokenRevealed)
          )
          .font(.system(.body, design: .monospaced))
          .textSelection(.enabled)
          .lineLimit(1)
          .truncationMode(.middle)
          .accessibilityIdentifier("settings.mcpToken")
        }

        HStack {
          Button(MCPSettingsModel.revealLabel(revealed: isTokenRevealed)) {
            isTokenRevealed.toggle()
          }
          Button(MCPSettingsModel.copyLabel) {
            coordinator.copyMCPTokenToPasteboard()
          }
          Spacer()
          Button(MCPSettingsModel.regenerateLabel) {
            coordinator.regenerateMCPToken()
          }
          .accessibilityIdentifier("settings.mcpRegenerate")
        }

        Text(MCPSettingsModel.regenerateNote)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .padding()
  }
}

/// What the server is doing, and whether that reads as a problem.
struct ServerStatusText: View {
  let state: MCPServerState

  var body: some View {
    Text(MCPSettingsModel.status(state))
      .font(.caption)
      .foregroundStyle(
        MCPSettingsModel.isWarning(state) ? AnyShapeStyle(.orange) : AnyShapeStyle(.secondary)
      )
      .accessibilityIdentifier("settings.mcpStatus")
  }
}

/// Shown only when the bound port is not the configured one.
struct ServerPortNote: View {
  let note: String?

  var body: some View {
    Text(note ?? "")
      .font(.caption)
      .foregroundStyle(.orange)
      .opacity(note == nil ? 0 : 1)
  }
}
