import AppKit

/// The floating pad window.
///
/// What is wanted is a window that floats above other applications, does not
/// activate Itchy when clicked, survives application deactivation, and appears
/// over fullscreen spaces — a combination SwiftUI has no vocabulary for, which
/// is why this is AppKit (specification §8.2).
final class PadPanel: NSPanel {
  private let configuration: PanelConfiguration

  /// Asked about every left-button press, before AppKit sees it (`FR-3.9`).
  /// Returns whether the press was consumed.
  var onTitleBarClick: ((_ clickCount: Int, _ inTitleBar: Bool) -> Bool)?

  /// Set by the controller while the panel is rolled up to its title bar.
  var isShaded = false

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
  ///
  /// Not while shaded: a key panel with no body would send every keystroke to
  /// an editor nobody can see (`FR-3.9`).
  override var canBecomeKey: Bool { configuration.canBecomeKey && !isShaded }

  /// False, so that interacting with a pad does not make Itchy the active
  /// application (`FR-3.1`).
  override var canBecomeMain: Bool { configuration.canBecomeMain }

  /// Intercepted here rather than in a view, because the title bar is the
  /// system's and has no view of ours to put a handler on (`FR-3.9`, D-34).
  ///
  /// Taken before `super`, since AppKit's own answer to a title-bar
  /// double-click is to zoom or minimise, according to a system setting, and a
  /// pad that zooms to fill the screen on the gesture meant to make it smaller
  /// is the worst available outcome. Both halves of the second click are
  /// consumed, because the title bar acts on the release; the first click goes
  /// through, which is what keeps the strip draggable.
  override func sendEvent(_ event: NSEvent) {
    switch event.type {
    case .leftMouseDown:
      isSwallowingRelease =
        onTitleBarClick?(event.clickCount, isInTitleBar(event.locationInWindow)) == true
      if isSwallowingRelease { return }
    case .leftMouseUp where isSwallowingRelease:
      // The title bar acts on the release, not the press: letting this one
      // through zooms the pad a moment after it was rolled up.
      isSwallowingRelease = false
      return
    default:
      break
    }
    super.sendEvent(event)
  }

  private var isSwallowingRelease = false

  /// Above the content layout rectangle is the title bar. Everything drawn
  /// below it — the accent rule included — is the pad's.
  private func isInTitleBar(_ point: NSPoint) -> Bool {
    point.y >= contentLayoutRect.maxY
  }

  /// The frame height of a panel whose content is `contentHeight` tall: the
  /// title bar, plus whatever of the content is to stay showing.
  func stripHeight(showingContent contentHeight: CGFloat) -> CGFloat {
    frameRect(forContentRect: NSRect(x: 0, y: 0, width: frame.width, height: contentHeight))
      .height
  }

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
