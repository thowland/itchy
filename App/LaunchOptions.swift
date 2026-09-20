import Foundation

/// What the launch arguments ask for.
///
/// A seam, so that `ItchyApp` stays free of conditionals (D-11) and so that the
/// parsing itself is tested rather than trusted. It exists for the UI suite: a
/// menubar-only application is awkward to drive through the status item, and a
/// UI test must never be pointed at the user's real pads.
struct LaunchOptions: Equatable, Sendable {
  /// Open a pad at launch, so the UI suite can reach a panel without driving the
  /// status item.
  var opensPadOnLaunch: Bool = false
  /// Use a throwaway storage root. Required whenever the suite runs, because
  /// otherwise the tests would create and delete pads in the real store.
  var usesTemporaryStorage: Bool = false
  /// A storage root the UI suite chose, so that it can arrange or damage a
  /// store between launches. Screenshot capture uses it to show a faulted pad.
  var storageRoot: String?
  /// Show About at launch instead of opening a pad, for screenshot capture.
  var showsAboutOnLaunch: Bool = false
  /// Show Settings at launch, for screenshot capture. A pad still opens
  /// underneath, because the Models section reads better over a pad than over
  /// an empty desktop.
  var showsSettingsOnLaunch: Bool = false
  /// Show the help book at launch, for screenshot capture.
  var showsHelpOnLaunch: Bool = false
  /// Which settings section to open at, named rather than numbered.
  var settingsTab: String?

  static let uiTestFlag = "-ItchyUITest"
  static let showAboutFlag = "-ItchyShowAbout"
  static let showSettingsFlag = "-ItchyShowSettings"
  static let showHelpFlag = "-ItchyShowHelp"
  static let storageRootVariable = "ITCHY_UI_TEST_ROOT"
  static let settingsTabVariable = "ITCHY_SETTINGS_TAB"

  /// The window flags and the storage root are honoured only alongside the
  /// UI-test flag. An ordinary launch ignores all of them, so nothing in the
  /// environment or the arguments can point a real launch at a different store
  /// or open a window nobody asked for.
  static func parse(_ arguments: [String], environment: [String: String] = [:]) -> LaunchOptions {
    guard arguments.contains(uiTestFlag) else { return LaunchOptions() }
    let showsAbout = arguments.contains(showAboutFlag)
    let showsSettings = arguments.contains(showSettingsFlag)
    let showsHelp = arguments.contains(showHelpFlag)
    return LaunchOptions(
      // About replaces the pad; Settings and Help sit over one, because both
      // read better with a pad behind them than against an empty desktop.
      opensPadOnLaunch: !showsAbout,
      usesTemporaryStorage: true,
      storageRoot: environment[storageRootVariable],
      showsAboutOnLaunch: showsAbout,
      showsSettingsOnLaunch: showsSettings,
      showsHelpOnLaunch: showsHelp,
      settingsTab: environment[settingsTabVariable])
  }

  static var current: LaunchOptions {
    parse(ProcessInfo.processInfo.arguments, environment: ProcessInfo.processInfo.environment)
  }
}
