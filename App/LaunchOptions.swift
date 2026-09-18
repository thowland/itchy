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

  static let uiTestFlag = "-ItchyUITest"
  static let showAboutFlag = "-ItchyShowAbout"
  static let storageRootVariable = "ITCHY_UI_TEST_ROOT"

  /// The About flag and the storage root are honoured only alongside the UI-test
  /// flag. An ordinary launch ignores both, so nothing in the environment can
  /// point a real launch at a different store.
  static func parse(_ arguments: [String], environment: [String: String] = [:]) -> LaunchOptions {
    guard arguments.contains(uiTestFlag) else { return LaunchOptions() }
    let showsAbout = arguments.contains(showAboutFlag)
    return LaunchOptions(
      opensPadOnLaunch: !showsAbout,
      usesTemporaryStorage: true,
      storageRoot: environment[storageRootVariable],
      showsAboutOnLaunch: showsAbout)
  }

  static var current: LaunchOptions {
    parse(ProcessInfo.processInfo.arguments, environment: ProcessInfo.processInfo.environment)
  }
}
