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

        Section {
          PadAccentControl(pad: pad, coordinator: coordinator)
        }

        Section {
          Picker(
            PadSettingsModel.routingLabel,
            selection: Binding(
              get: { coordinator.metadata(for: pad).routingPolicy },
              set: { coordinator.setRoutingPolicy(pad.id, $0) })
          ) {
            ForEach(RoutingPolicy.allCases, id: \.self) { policy in
              Text(PadSettingsModel.routingChoice(policy)).tag(policy)
            }
          }
          .pickerStyle(.inline)
          .accessibilityIdentifier("pad.settings.routing")
          PadSettingsNotice(
            notice: PadSettingsModel.routingNote(coordinator.metadata(for: pad).routingPolicy))
        }

        Section {
          Toggle(
            MCPSettingsModel.exposureLabel,
            isOn: Binding(
              get: { coordinator.metadata(for: pad).isExposedToMCP },
              set: { coordinator.setExposedToMCP(pad.id, $0) })
          )
          .accessibilityIdentifier("pad.settings.exposure")
          PadSettingsNotice(
            notice: MCPSettingsModel.exposureNote(
              isExposed: coordinator.metadata(for: pad).isExposedToMCP,
              serverEnabled: coordinator.settings.mcpServerEnabled))
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

/// The accent rule's control (`FR-3.8`, D-33).
///
/// Its own view because the colour well is shown only for a custom colour, and
/// `PadSettingsView` is on the coverage exclusion list and may not branch.
/// Whether the well appears, and what each row is worth, are `PadAccentModel`'s.
struct PadAccentControl: View {
  let pad: PadMetadata
  let coordinator: PadCoordinator

  var body: some View {
    let accent = coordinator.metadata(for: pad).accent
    Picker(
      PadAccentModel.label,
      selection: Binding(
        get: { PadAccentModel.choice(for: accent) },
        set: { coordinator.setAccent(pad.id, PadAccentModel.accent(for: $0, current: accent)) })
    ) {
      ForEach(PadAccentModel.all, id: \.self) { choice in
        Text(PadAccentModel.title(choice)).tag(choice)
      }
    }
    .accessibilityIdentifier("pad.settings.accent")

    PadAccentWell(accent: accent) { chosen in
      coordinator.setAccent(pad.id, chosen)
    }
    PadSettingsNotice(notice: PadAccentModel.note(for: accent))
  }
}

/// The colour well, present only when the pad is on a custom colour.
struct PadAccentWell: View {
  let accent: PadAccent?
  let onChange: (PadAccent?) -> Void

  var body: some View {
    ColorPicker(
      PadAccentModel.customLabel,
      selection: Binding(
        get: { AccentColorCodec.swiftUIColor(PadAccentPalette.rgb(of: resolved, in: .light)) },
        set: { chosen in
          guard let rgb = AccentColorCodec.rgb(chosen) else { return }
          onChange(.custom(rgb))
        }),
      supportsOpacity: false
    )
    .accessibilityIdentifier("pad.settings.accent.colour")
    .opacity(PadAccentModel.showsColorWell(for: accent) ? 1 : 0)
    .frame(height: PadAccentModel.showsColorWell(for: accent) ? nil : 0)
  }

  /// A colour to show while there is none. The well is hidden in that case, so
  /// this is never what somebody sees; it exists because a `ColorPicker` needs
  /// a binding whether or not it is on screen.
  private var resolved: PadAccent {
    accent ?? .named(.slate)
  }
}
