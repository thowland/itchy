import ItchyCore
import SwiftUI

/// The Models section (§10, §12, `FR-9.4`, `FR-9.5`).
///
/// On the coverage exclusion list and so may not branch: wording, trimming and
/// what counts as configured are `ModelSettingsModel`'s.
///
/// Each row is a labelled `TextField` rather than a `TextField` inside a
/// `LabeledContent`. In a `Form` the field's first argument is rendered as its
/// leading label, so wrapping it labels the row twice and prints the value
/// beside the field that holds it — which is what the window did until it was
/// screenshotted.
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
        TextField(
          ModelSettingsModel.localEndpointLabel,
          text: Binding(
            get: { coordinator.settings.models.localEndpoint },
            set: { coordinator.setModelSettings(models(localEndpoint: $0)) }),
          prompt: Text(ModelSettings.defaultLocalEndpoint)
        )
        .accessibilityIdentifier("settings.localEndpoint")

        TextField(
          ModelSettingsModel.localModelLabel,
          text: Binding(
            get: { coordinator.settings.models.localModel },
            set: { coordinator.setModelSettings(models(localModel: $0)) }),
          prompt: Text(ModelSettingsModel.localModelPlaceholder)
        )
        .accessibilityIdentifier("settings.localModel")

        Text(ModelSettingsModel.localCaption)
          .font(.caption)
          .foregroundStyle(.secondary)
      }

      Section(ModelSettingsModel.remoteHeading) {
        TextField(
          ModelSettingsModel.remoteEndpointLabel,
          text: Binding(
            get: { coordinator.settings.models.remoteEndpoint },
            set: { coordinator.setModelSettings(models(remoteEndpoint: $0)) }),
          prompt: Text(ModelSettingsModel.remoteEndpointPlaceholder)
        )

        TextField(
          ModelSettingsModel.remoteModelLabel,
          text: Binding(
            get: { coordinator.settings.models.remoteModel },
            set: { coordinator.setModelSettings(models(remoteModel: $0)) }),
          prompt: Text(ModelSettingsModel.remoteModelPlaceholder)
        )

        HStack {
          SecureField(ModelSettingsModel.remoteKeyLabel, text: $apiKey)
            .accessibilityIdentifier("settings.remoteKey")
          Button("Save") {
            coordinator.setRemoteAPIKey(apiKey)
            apiKey = ""
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

  /// One field changed, the rest carried over and trimmed. Here rather than at
  /// four call sites so the view stays a list of rows.
  private func models(
    localEndpoint: String? = nil,
    localModel: String? = nil,
    remoteEndpoint: String? = nil,
    remoteModel: String? = nil
  ) -> ModelSettings {
    ModelSettingsModel.settings(
      from: coordinator.settings.models,
      localEndpoint: localEndpoint,
      localModel: localModel,
      remoteEndpoint: remoteEndpoint,
      remoteModel: remoteModel)
  }
}
