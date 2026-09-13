import ItchyCore
import SwiftUI

/// One pad's settings, shown as a sheet on its panel (D-21).
///
/// On the coverage exclusion list, so it may not branch. Mode and pinning apply
/// as they change; the name applies on Return and whenever the sheet closes,
/// so it is not renamed once per keystroke. Validation is `PadSettingsModel`'s.
struct PadSettingsView: View {
  let pad: PadMetadata
  let coordinator: PadCoordinator
  @Environment(\.dismiss) private var dismiss
  @State private var draftName: String

  init(pad: PadMetadata, coordinator: PadCoordinator) {
    self.pad = pad
    self.coordinator = coordinator
    _draftName = State(initialValue: pad.name)
  }

  var body: some View {
    VStack(alignment: .leading, spacing: 0) {
      Text(PadSettingsModel.title(for: coordinator.metadata(for: pad)))
        .font(.headline)
        .padding([.top, .horizontal])

      Form {
        Section {
          TextField("Name", text: $draftName)
            .onSubmit { coordinator.applyName(draftName, to: pad.id) }
            .accessibilityIdentifier("pad.settings.name")
          PadSettingsNotice(
            notice: PadSettingsModel.notice(
              draft: draftName, padID: pad.id, pads: coordinator.pads))
        }

        Section {
          Picker(
            "Mode",
            selection: Binding(
              get: { coordinator.metadata(for: pad).mode },
              set: { coordinator.setMode(pad.id, to: $0) })
          ) {
            ForEach(PadMode.allCases, id: \.self) { mode in
              Text(SettingsModel.defaultModeLabel(mode)).tag(mode)
            }
          }
          .pickerStyle(.inline)

          Toggle(
            PadSettingsModel.pinnedLabel,
            isOn: Binding(
              get: { coordinator.metadata(for: pad).isPinned },
              set: { coordinator.setPinned(pad.id, $0) }))
        }
      }
      .formStyle(.grouped)

      HStack {
        Spacer()
        Button("Done") { dismiss() }
          .keyboardShortcut(.defaultAction)
          .accessibilityIdentifier("pad.settings.done")
      }
      .padding([.horizontal, .bottom])
    }
    .frame(width: 380)
    .onDisappear { coordinator.applyName(draftName, to: pad.id) }
  }
}

/// Shown only when there is something to say about the name.
struct PadSettingsNotice: View {
  let notice: String?

  var body: some View {
    Text(notice ?? "")
      .font(.caption)
      .foregroundStyle(.orange)
      .opacity(notice == nil ? 0 : 1)
  }
}
