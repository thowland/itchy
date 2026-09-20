import AppKit

/// The floating pad window.
///
/// What is wanted is a window that floats above other applications, does not
/// activate Itchy when clicked, survives application deactivation, and appears
/// over fullscreen spaces — a combination SwiftUI has no vocabulary for, which
/// is why this is AppKit (specification §8.2).
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

  /// Stated, because AppKit's default for this panel is wrong (D-33).
  ///
  /// A titled `NSPanel` that is not a utility window reports its subrole as
  /// `AXDialog`. A pad is not a dialog: nothing is waiting on it, it takes no
  /// answer, and it does not go away when you have dealt with it. VoiceOver
  /// announces it as one, and XCUITest classifies it as a dialog rather than a
  /// window, which is how this was found — every query in the UI suite reads
  /// `app.windows` and all of them stopped matching at once.
  ///
  /// `AXFloatingWindow` is what it actually is, and what the utility style mask
  /// used to report before it was dropped for the sake of a legible title.
  override func accessibilitySubrole() -> NSAccessibility.Subrole? {
    .floatingWindow
  }
}
