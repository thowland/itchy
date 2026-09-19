import AppKit
import ItchyCore

/// Creating, naming, ordering and removing pads.
///
/// Split from `PadCoordinator` for the reason the hotkey and archive
/// extensions were: the type outgrew its body limit, and these seven belong
/// together — they are the operations the Pads window drives.
extension PadCoordinator {
  /// `FR-2.3`: creation requires no input and the pad is immediately ready to
  /// accept typing — so it opens, focused, rather than only appearing in a list
  /// the user then has to go and click.
  func createPad() {
    Task { [weak self] in
      guard let self else { return }
      guard let created = try? await self.store.createPad(name: nil) else { return }
      try? await self.store.setMode(created.id, to: self.settings.defaultMode)
      DebugLog.shared.record(.padCreated(created.id, name: created.name, by: .user))
      await self.refresh()
      await self.openPad(created.id, makingKey: true)
    }
  }

  func rename(_ padID: PadID, to name: String) {
    Task { [weak self] in
      guard let self else { return }
      try? await self.store.rename(padID, to: name)
      await self.refresh()
      // `FR-2.4`: the panel title is set when the panel is created, and an open
      // pad kept its old name there until it was closed and reopened.
      self.registry.controller(for: padID)?.panel.title = name
    }
  }

  func setPinned(_ padID: PadID, _ pinned: Bool) {
    Task { [weak self] in
      guard let self else { return }
      try? await self.store.setPinned(padID, pinned)
      await self.refresh()
    }
  }

  /// `FR-2.6`: deletion is the one destructive action, and the only place a
  /// confirmation is shown. The dialogue is in `PadsWindowView`; this is what it
  /// calls once the user has said yes.
  func deletePad(_ padID: PadID) {
    Task { [weak self] in
      guard let self else { return }
      DebugLog.shared.record(
        .padDeleted(padID, name: self.pads.first { $0.id == padID }?.name ?? "—"))
      self.registry.close(padID)
      self.editors[padID] = nil
      try? await self.store.deletePad(padID)
      await self.refresh()
    }
  }

  /// `FR-2.6`: emptying is a single action and, while the panel is open, one
  /// undo restores the content exactly.
  func emptyPad(_ padID: PadID) {
    Task { [weak self] in
      guard let self else { return }
      guard let editor = self.editors[padID] else {
        try? await self.store.empty(padID)
        await self.refresh()
        return
      }
      editor.apply(NSAttributedString(), actionName: "Empty Pad")
    }
  }

  /// `FR-4.9`: copying a pad's entire contents as plain text is a single action.
  func copyAsPlainText(_ padID: PadID) {
    Task { [weak self] in
      guard let self else { return }
      guard let content = try? await self.store.content(of: padID) else { return }
      NSPasteboard.general.clearContents()
      NSPasteboard.general.setString(content.plainText, forType: .string)
    }
  }

  func reorder(from source: IndexSet, to destination: Int) {
    var order = pads.map(\.id)
    order.move(fromOffsets: source, toOffset: destination)
    Task { [weak self] in
      guard let self else { return }
      try? await self.store.reorder(to: order)
      await self.refresh()
    }
  }
}
