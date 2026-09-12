import AppKit

/// The floating pad window.
///
/// What is wanted is a utility window that floats above other applications, does
/// not activate Itchy when clicked, survives application deactivation, and
/// appears over fullscreen spaces — a combination SwiftUI has no vocabulary for,
/// which is why this is AppKit (specification §8.2).
final class PadPanel: NSPanel {
  private let configuration: PanelConfiguration

  init(configuration: PanelConfiguration = .standard, contentRect: NSRect) {
    self.configuration = configuration
    super.init(
      contentRect: contentRect,
      styleMask: configuration.styleMask,
      backing: .buffered,
      defer: false)
    apply(configuration)
  }

  private func apply(_ configuration: PanelConfiguration) {
    isFloatingPanel = configuration.isFloatingPanel
    level = configuration.level
    collectionBehavior = configuration.collectionBehavior
    hidesOnDeactivate = configuration.hidesOnDeactivate
    isReleasedWhenClosed = configuration.isReleasedWhenClosed
    animationBehavior = .utilityWindow
    minSize = configuration.minimumSize
    titlebarAppearsTransparent = false
    isMovableByWindowBackground = true
  }

  /// `FR-3.2`. Without this the panel appears correctly and refuses every
  /// keystroke, which is the failure specification §8.2 predicts and the one
  /// Sprint 2's exit gate tests for.
  override var canBecomeKey: Bool { configuration.canBecomeKey }

  /// False, so that interacting with a pad does not make Itchy the active
  /// application (`FR-3.1`).
  override var canBecomeMain: Bool { configuration.canBecomeMain }
}
