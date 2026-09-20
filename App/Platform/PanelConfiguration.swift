import AppKit

/// How a pad panel is configured, as a value.
///
/// Stated as data rather than as a sequence of property assignments so that the
/// configuration can be asserted in a test without a window server (D-11). Every
/// field here is a requirement, and specification §8.2 gives the table this
/// mirrors — a deviation from it is a bug rather than a preference.
struct PanelConfiguration: Equatable, Sendable {
  var styleMask: NSWindow.StyleMask
  var level: NSWindow.Level
  var collectionBehavior: NSWindow.CollectionBehavior
  var isFloatingPanel: Bool
  var hidesOnDeactivate: Bool
  var isReleasedWhenClosed: Bool
  /// Overridden to true. A non-activating panel does not become key by default,
  /// and the symptom is a panel that looks entirely correct and silently
  /// discards every keystroke (`FR-3.2`).
  var canBecomeKey: Bool
  /// False, so that clicking a pad does not make Itchy the active application
  /// (`FR-3.1`).
  var canBecomeMain: Bool
  var minimumSize: NSSize

  /// `.utilityWindow` is deliberately absent (D-33). It was here until the
  /// title proved too small and too light to read at a glance, which is what a
  /// utility window's short title bar gives you and what no supported API can
  /// restyle. Dropping it buys the standard bold title; the floating,
  /// non-activating behaviour `FR-3.1` asks for comes from `.nonactivatingPanel`,
  /// `isFloatingPanel` and `level`, none of which change.
  static let standard = PanelConfiguration(
    styleMask: [.titled, .closable, .resizable, .nonactivatingPanel],
    level: .floating,
    collectionBehavior: [.canJoinAllSpaces, .fullScreenAuxiliary],
    isFloatingPanel: true,
    hidesOnDeactivate: false,
    isReleasedWhenClosed: false,
    canBecomeKey: true,
    canBecomeMain: false,
    minimumSize: NSSize(width: 240, height: 160))

  /// The default size and position for a pad that has never been opened.
  static let defaultSize = NSSize(width: 420, height: 520)
}
