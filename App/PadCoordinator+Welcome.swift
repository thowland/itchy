import AppKit

/// The first-run window, and the About screen that reuses it (D-22).
///
/// Split from `PadCoordinator` for the same reason as the hotkey extension: the
/// type outgrew its body limit, and this is a distinct responsibility.
extension PadCoordinator {
  /// Says once where to look, because an accessory application with no Dock
  /// icon and no window otherwise starts silently. The decision is
  /// `FirstRunPolicy`'s.
  func showWelcomeIfNeeded() {
    guard FirstRunPolicy.shouldShowWelcome(settings: settings, launchOptions: launchOptions)
    else { return }
    presentWelcome(.firstRun)
  }

  internal func presentWelcome(_ presentation: WelcomePresentation) {
    let controller = WelcomeWindowController(
      presentation: presentation,
      onDismiss: { [weak self] in self?.welcomeDismissed(presentation) },
      onHelp: { [weak self] in self?.showHelp() })
    welcome = controller
    controller.show()
  }

  fileprivate func welcomeDismissed(_ presentation: WelcomePresentation) {
    welcome = nil
    guard FirstRunPolicy.dismissal(for: presentation) == .recordFirstRun else { return }
    settings.hasCompletedFirstRun = true
    persistSettings()
  }

  var isShowingWelcome: Bool { welcome?.isVisible ?? false }

  /// Why the welcome window is up, or nil when it is not.
  var welcomePresentation: WelcomePresentation? { welcome?.presentation }

  /// Closes the welcome window. Exactly what its button does, reachable without
  /// a mouse so the flow can be tested.
  func dismissWelcome() {
    welcome?.dismiss()
  }

  func showAbout() {
    switch FirstRunPolicy.aboutRequest(showing: welcomePresentation) {
    case .open: presentWelcome(.about)
    case .raiseExisting: welcome?.show()
    }
  }
}
