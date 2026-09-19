import ItchyCore
import SwiftUI

/// The Models section (§10, §12, `FR-9.4`, `FR-9.5`).
///
/// On the coverage exclusion list and so may not branch: wording, trimming and
/// what counts as configured are `ModelSettingsModel`'s.
struct ModelSettingsView: View {
  @Environment(PadCoordinator.self) private var coordinator
  @State private var apiKey = ""

  var body: some View {
    Form {
      Section {
        Text(ModelSettingsModel.status(coordinator.settings.models))
          .font(.caption)
          .foregroundStyle(.secondary)
          .accessibilityIdentifier("settings.modelStatus")
      }

      Section(ModelSettingsModel.localHeading) {
        LabeledContent(ModelSettingsModel.localEndpointLabel) {
          TextField(
            ModelSettings.defaultLocalEndpoint,
            text: Binding(
              get: { coordinator.settings.models.localEndpoint },
              set: {
                coordinator.setModelSettings(
                  ModelSettingsModel.settings(
                    from: coordinator.settings.models, localEndpoint: $0))
              })
          )
          .accessibilityIdentifier("settings.localEndpoint")
        }
        LabeledContent(ModelSettingsModel.localModelLabel) {
          TextField(
            ModelSettingsModel.localModelPlaceholder,
            text: Binding(
              get: { coordinator.settings.models.localModel },
              set: {
                coordinator.setModelSettings(
                  ModelSettingsModel.settings(from: coordinator.settings.models, localModel: $0))
              })
          )
          .accessibilityIdentifier("settings.localModel")
        }
        Text(ModelSettingsModel.localCaption)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section(ModelSettingsModel.remoteHeading) {
        LabeledContent(ModelSettingsModel.remoteEndpointLabel) {
          TextField(
            ModelSettingsModel.remoteEndpointPlaceholder,
            text: Binding(
              get: { coordinator.settings.models.remoteEndpoint },
              set: {
                coordinator.setModelSettings(
                  ModelSettingsModel.settings(
                    from: coordinator.settings.models, remoteEndpoint: $0))
              })
          )
        }
        LabeledContent(ModelSettingsModel.remoteModelLabel) {
          TextField(
            ModelSettingsModel.remoteModelPlaceholder,
            text: Binding(
              get: { coordinator.settings.models.remoteModel },
              set: {
                coordinator.setModelSettings(
                  ModelSettingsModel.settings(from: coordinator.settings.models, remoteModel: $0))
              })
          )
        }
        LabeledContent(ModelSettingsModel.remoteKeyLabel) {
          HStack {
            SecureField("", text: $apiKey)
              .accessibilityIdentifier("settings.remoteKey")
            Button("Save") {
              coordinator.setRemoteAPIKey(apiKey)
              apiKey = ""
            }
          }
        }
        Text(ModelSettingsModel.keyDisplay(hasKey: coordinator.hasRemoteAPIKey))
          .font(.caption)
        Text(ModelSettingsModel.keyCaption)
          .font(.caption)
          .foregroundStyle(.secondary)
        Text(ModelSettingsModel.remoteCaption)
          .font(.caption)
          .foregroundStyle(.secondary)
      }
    }
    .formStyle(.grouped)
    .padding()
  }
}
