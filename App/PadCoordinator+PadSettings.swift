import AppKit
import ItchyCore

/// A pad's own settings (D-21), and the live metadata an open panel shows.
extension PadCoordinator {
  /// The pad as it is now.
  ///
  /// A panel is built with the metadata of the moment it opened. Without this it
  /// kept showing that name and mode after either changed, in the status bar, in
  /// the actions menu, and in whether the formatting controls appear.
  func metadata(for pad: PadMetadata) -> PadMetadata {
    pads.first { $0.id == pad.id } ?? pad
  }

  /// Renames from the pad's settings, if the draft is a name worth keeping.
  func applyName(_ draft: String, to padID: PadID) {
    guard let current = pads.first(where: { $0.id == padID }) else { return }
    switch PadSettingsModel.nameChange(draft: draft, current: current.name) {
    case .rename(let name): rename(padID, to: name)
    case .unchanged: break
    }
  }

  /// `NFR-3.2`: exposure is per pad, opt in, and never a default for a pad the
  /// person made. This is the only way one becomes exposed other than an agent
  /// creating it, and the pad says so on itself while it is.
  func setExposedToMCP(_ padID: PadID, _ exposed: Bool) {
    Task { [weak self] in
      guard let self else { return }
      try? await self.store.setExposedToMCP(padID, exposed)
      DebugLog.shared.record(
        .exposureChanged(
          self.pads.first { $0.id == padID }?.name ?? padID.description, exposed: exposed))
      await self.refresh()
    }
  }

  /// `FR-9.1`: the policy is the person's, per pad, and local-only until they
  /// say otherwise.
  func setRoutingPolicy(_ padID: PadID, _ policy: RoutingPolicy) {
    Task { [weak self] in
      guard let self else { return }
      try? await self.store.setRoutingPolicy(padID, policy)
      await self.refresh()
    }
  }

  /// `FR-3.8`: the accent rule is the person's, per pad, and off until they
  /// set one. Nil turns it off.
  func setAccent(_ padID: PadID, _ accent: PadAccent?) {
    Task { [weak self] in
      guard let self else { return }
      try? await self.store.setAccent(padID, accent)
      await self.refresh()
    }
  }

  /// `FR-7.5`: clearing the list leaves the pad's content alone. The store
  /// already separates them — provenance is metadata, never text attributes
  /// (`FR-7.2`) — so this is a metadata write and touches no content.
  func clearProvenance(_ padID: PadID) {
    Task { [weak self] in
      guard let self else { return }
      await self.store.clearProvenance(of: padID)
      await self.refresh()
    }
  }

  /// Makes Itchy active before a pad's settings sheet appears.
  ///
  /// A pad panel takes the keyboard without activating the application
  /// (D-14), but a sheet is an ordinary window and does not share that
  /// exemption: without activation its name field shows a cursor and discards
  /// every keystroke.
  func prepareForPadSettings() {
    NSApp.activate(ignoringOtherApps: true)
  }
}
