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
