import ItchyCore
import SwiftUI

/// Backups (D-18).
///
/// The wording lives in `ArchiveSettingsText`; this file is on the coverage
/// exclusion list and may not branch.
struct ArchiveSettingsView: View {
  @Environment(PadCoordinator.self) private var coordinator

  var body: some View {
    Form {
      Section {
        Stepper(
          value: Binding(
            get: { coordinator.settings.archiveRetention },
            set: { coordinator.setArchiveRetention($0) }),
          in: ArchiveBounds.disabled...ArchiveBounds.maximumRetention
        ) {
          Text(ArchiveSettingsText.retentionLabel(coordinator.settings.archiveRetention))
        }
        Text(ArchiveSettingsText.retentionCaption(coordinator.settings.archiveRetention))
          .font(.caption)
          .foregroundStyle(.secondary)

        Toggle(
          "Also keep a daily backup",
          isOn: Binding(
            get: { coordinator.settings.archivesDaily },
            set: { coordinator.setArchivesDaily($0) })
        )
        .disabled(coordinator.settings.archiveRetention == ArchiveBounds.disabled)
      }

      Section {
        LabeledContent("Kept now") {
          Text(
            ArchiveSettingsText.summary(
              count: coordinator.archives.count, bytes: coordinator.archiveTotalBytes))
        }
        HStack {
          Button("Show in Finder") { coordinator.revealArchives() }
          Spacer()
          Button("Delete All Backups", role: .destructive) {
            coordinator.removeAllArchives()
          }
        }
      }
    }
    .formStyle(.grouped)
    .padding()
  }
}
