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

  static let uiTestFlag = "-ItchyUITest"

  static func parse(_ arguments: [String]) -> LaunchOptions {
    let isUITest = arguments.contains(uiTestFlag)
    return LaunchOptions(opensPadOnLaunch: isUITest, usesTemporaryStorage: isUITest)
  }

  static var current: LaunchOptions {
    parse(ProcessInfo.processInfo.arguments)
  }
}
