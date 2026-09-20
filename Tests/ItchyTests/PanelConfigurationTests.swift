import AppKit
import Testing

@testable import Itchy

/// The configuration is asserted as a value rather than by inspecting a live
/// window, which is what lets these run without a window server (D-11).
///
/// Specification §8.2 states this table and calls a deviation from it a bug.
@Suite("Panel configuration")
struct PanelConfigurationTests {
  private let configuration = PanelConfiguration.standard

  /// `FR-3.2`. The single detail most likely to cost an afternoon: a
  /// non-activating panel does not become key by default, and the symptom is a
  /// panel that looks entirely correct and discards every keystroke.
  @Test("The panel can become key")
  func canBecomeKey() {
    #expect(configuration.canBecomeKey)
  }

  /// `FR-3.1`: interacting with a pad must not make Itchy the active
  /// application.
  @Test("The panel cannot become main")
  func cannotBecomeMain() {
    #expect(!configuration.canBecomeMain)
  }

  @Test("The style mask is the one the specification states")
  func styleMask() {
    #expect(configuration.styleMask.contains(.titled))
    #expect(configuration.styleMask.contains(.closable))
    #expect(configuration.styleMask.contains(.resizable))
    #expect(configuration.styleMask.contains(.nonactivatingPanel))
    // Absent on purpose (D-33): a utility window draws a short title bar with a
    // small, light title, and there is no supported way to restyle a
    // system-drawn title. Floating and non-activating come from the flags
    // above and from `level`, so dropping it costs none of `FR-3.1`.
    #expect(!configuration.styleMask.contains(.utilityWindow))
  }

  @Test("It floats above other applications")
  func floats() {
    #expect(configuration.isFloatingPanel)
    #expect(configuration.level == .floating)
  }

  /// `FR-3.1`: the pad stays visible while the user works in another
  /// application, and follows them over fullscreen.
  @Test("It survives deactivation and appears over fullscreen spaces")
  func survivesDeactivation() {
    #expect(!configuration.hidesOnDeactivate)
    #expect(configuration.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(configuration.collectionBehavior.contains(.fullScreenAuxiliary))
  }

  @Test("The controller owns the panel's lifetime")
  func notReleasedWhenClosed() {
    #expect(!configuration.isReleasedWhenClosed)
  }

  @Test("A minimum size keeps the status bar legible")
  func minimumSize() {
    #expect(configuration.minimumSize.width >= 240)
    #expect(configuration.minimumSize.height >= 160)
  }

  /// The value and the window must not drift apart, so the panel is built and
  /// its properties compared against the configuration it was given.
  @MainActor
  @Test("A built panel matches the configuration it was given")
  func builtPanelMatches() {
    let panel = PadPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520))
    #expect(panel.canBecomeKey == configuration.canBecomeKey)
    #expect(panel.canBecomeMain == configuration.canBecomeMain)
    #expect(panel.isFloatingPanel == configuration.isFloatingPanel)
    #expect(panel.level == configuration.level)
    #expect(panel.hidesOnDeactivate == configuration.hidesOnDeactivate)
    #expect(panel.collectionBehavior.contains(.fullScreenAuxiliary))
    #expect(panel.collectionBehavior.contains(.canJoinAllSpaces))
    #expect(panel.minSize == configuration.minimumSize)
  }

  /// Regression, and the reason it is worth a test of its own (D-33).
  ///
  /// A titled `NSPanel` that is not a utility window reports `AXDialog`, and a
  /// pad is not a dialog — nothing waits on it and it takes no answer.
  /// VoiceOver says so out loud, and every `app.windows` query in the UI suite
  /// stops matching at once, which is a loud failure for a quiet mistake. The
  /// subrole is therefore stated rather than inherited, and asserted here so
  /// that a future change to the style mask cannot take it away silently.
  @MainActor
  @Test("A pad is a floating window rather than a dialog")
  func accessibilitySubrole() {
    let panel = PadPanel(contentRect: NSRect(x: 0, y: 0, width: 420, height: 520))
    #expect(panel.accessibilitySubrole() == .floatingWindow)
  }
}
