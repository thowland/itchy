import ItchyCore
import SwiftUI

/// The pad management window, reached from the menubar's "Pads…".
///
/// Rename, reorder, pin and delete live here rather than in the menubar, which
/// stays a list of pads to open (specification §8.1).
struct PadsWindowView: View {
  @Environment(PadCoordinator.self) private var coordinator
  @State private var selection: PadID?
  @State private var pendingDeletion: PadMetadata?

  var body: some View {
    VStack(spacing: 0) {
      List(selection: $selection) {
        ForEach(coordinator.pads) { pad in
          PadRowView(pad: pad, coordinator: coordinator)
            .tag(pad.id)
        }
        .onMove { source, destination in
          coordinator.reorder(from: source, to: destination)
        }
      }
      Divider()
      PadsToolbar(
        selection: selection,
        onCreate: { coordinator.createPad() },
        onDelete: { pendingDeletion = coordinator.pads.first { $0.id == selection } })
    }
    .frame(minWidth: 420, minHeight: 280)
    .confirmationDialog(
      DeletionPrompt.title(for: pendingDeletion),
      isPresented: Binding(
        get: { pendingDeletion != nil },
        set: { shown in pendingDeletion = shown ? pendingDeletion : nil }),
      titleVisibility: .visible
    ) {
      Button("Delete Pad", role: .destructive) {
        DeletionPrompt.perform(pendingDeletion, with: coordinator)
        pendingDeletion = nil
      }
      Button("Cancel", role: .cancel) { pendingDeletion = nil }
    } message: {
      Text(DeletionPrompt.message)
    }
  }
}

/// One pad's row: rename in place, pin, mode.
struct PadRowView: View {
  let pad: PadMetadata
  let coordinator: PadCoordinator

  var body: some View {
    HStack(spacing: 10) {
      Button {
        coordinator.setPinned(pad.id, !pad.isPinned)
      } label: {
        Image(systemName: pad.isPinned ? "pin.fill" : "pin")
      }
      .buttonStyle(.borderless)
      .help("Pinned pads reopen at launch")
      .accessibilityLabel(pad.isPinned ? "Unpin \(pad.name)" : "Pin \(pad.name)")

      TextField(
        "Name",
        text: Binding(
          get: { pad.name },
          set: { coordinator.rename(pad.id, to: $0) })
      )
      .textFieldStyle(.plain)
      .accessibilityLabel("Pad name")

      Picker(
        "",
        selection: Binding(
          get: { pad.mode },
          set: { coordinator.setMode(pad.id, to: $0) })
      ) {
        ForEach(PadMode.allCases, id: \.self) { mode in
          Text(mode.rawValue).tag(mode)
        }
      }
      .labelsHidden()
      .frame(width: 90)
      .accessibilityLabel("Mode for \(pad.name)")
    }
    .padding(.vertical, 2)
  }
}

struct PadsToolbar: View {
  let selection: PadID?
  let onCreate: () -> Void
  let onDelete: () -> Void

  var body: some View {
    HStack {
      Button(action: onCreate) { Image(systemName: "plus") }
        .help("New pad")
        .accessibilityLabel("New pad")
      Button(action: onDelete) { Image(systemName: "minus") }
        .disabled(selection == nil)
        .help("Delete pad")
        .accessibilityLabel("Delete selected pad")
      Spacer()
    }
    .buttonStyle(.borderless)
    .padding(8)
  }
}

/// The wording and the action behind the one confirmation Itchy shows.
///
/// `CON-2` prohibits prompts; `FR-2.6` makes deletion the single exception,
/// because the action is destructive rather than organisational.
@MainActor
enum DeletionPrompt {
  nonisolated static func title(for pad: PadMetadata?) -> String {
    guard let pad else { return "Delete this pad?" }
    return "Delete “\(pad.name)”?"
  }

  nonisolated static let message =
    "The pad and everything in it will be removed. This cannot be undone."

  static func perform(_ pad: PadMetadata?, with coordinator: PadCoordinator) {
    guard let pad else { return }
    coordinator.deletePad(pad.id)
  }
}
