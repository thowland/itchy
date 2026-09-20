import AppKit

/// The settings window, which `SettingsWindowController` owns and explains.
extension PadCoordinator {
  /// Opens settings in front of everything, pads included.
  func showSettings(tab: SettingsTab = .general) {
    settingsWindow.show(tab: tab)
  }

  var isShowingSettings: Bool { settingsWindow.isVisible }

  func closeSettings() {
    settingsWindow.close()
  }
}
