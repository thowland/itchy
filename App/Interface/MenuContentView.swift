import AppKit
import ItchyCore
import SwiftUI

/// Menubar contents.
///
/// Renders the rows `MenuModel` produces and nothing else: ordering, slot
/// numbers, size markers, faulted presentation and key equivalents are all
/// decided there (D-11, specification §15.2).
struct MenuContentView: View {
  @Environment(PadCoordinator.self) private var coordinator

  var body: some View {
    ForEach(coordinator.rows) { row in
      MenuRowButton(row: row) {
        coordinator.open(row.id)
      }
    }
    EmptyStateText(isEmpty: coordinator.rows.isEmpty)
    Divider()
    Button("New Pad") {
      coordinator.createPad()
    }
    .keyboardShortcut("n")
    PadsWindowLink()
    Divider()
    Button("Settings…") {
      SettingsPresenter.show()
    }
    .keyboardShortcut(",")
    Button("Quit Itchy") {
      NSApplication.shared.terminate(nil)
    }
    .keyboardShortcut("q")
  }
}

/// One pad's row.
struct MenuRowButton: View {
  let row: MenuRow
  let action: () -> Void

  var body: some View {
    Button(MenuRowLabel.text(for: row), action: action)
      .keyboardShortcut(MenuRowLabel.shortcut(for: row), modifiers: [.control, .option])
  }
}

/// Opens the pad management window, where rename, reorder, pin and delete live.
struct PadsWindowLink: View {
  @Environment(\.openWindow) private var openWindow

  var body: some View {
    Button("Pads…") {
      openWindow(id: WindowIdentifier.pads)
    }
  }
}

/// Shown only when there are no pads at all.
struct EmptyStateText: View {
  let isEmpty: Bool

  var body: some View {
    Text(MenuModel.emptyTitle)
      .opacity(isEmpty ? 1 : 0)
      .frame(height: isEmpty ? nil : 0)
  }
}
