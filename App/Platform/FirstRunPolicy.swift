import Foundation
import ItchyCore

/// Whether to show the welcome window (D-11).
///
/// A decision rather than a branch in the launch path, because it has three
/// conditions and one of them — suppressing it under test — is the kind of thing
/// that is easy to forget and then presents as the UI suite failing for no
/// visible reason.
enum FirstRunPolicy {
  static func shouldShowWelcome(
    settings: AppSettings,
    launchOptions: LaunchOptions
  ) -> Bool {
    // A UI test drives panels, and a window it did not ask for sits in front of
    // them. The suite would fail on a perfectly working application.
    guard !launchOptions.opensPadOnLaunch else { return false }
    return !settings.hasCompletedFirstRun
  }
}

/// What the welcome window says.
///
/// Held here rather than in the view so the wording is reviewable in one place —
/// and so a view file, which may not branch, does not have to assemble it.
enum WelcomeText {
  static let title = "Itchy"
  static let tagline = "A scratchpad that lives in your menubar."

  static let points: [(symbol: String, text: String)] = [
    (
      "menubar.rectangle",
      "Everything is run from the cat in the menubar. Itchy has no Dock icon and "
        + "no window of its own — if it looks like nothing happened, look up there."
    ),
    (
      "square.on.square.dashed",
      "Click a pad to open it. Pads float above whatever you are working in, and "
        + "stay put when you click away."
    ),
    (
      "keyboard",
      "Press ⌃⌥Space from anywhere to bring back the pad you used last. Press it "
        + "again to put it away."
    ),
    (
      "tray.full",
      "Nothing needs saving, naming or filing. Type or paste, close the window, "
        + "and it is still there next time."
    ),
  ]

  static let authorLine = "Built by Tim Howland"
  static let websiteTitle = "timhowland.com"
  static let websiteAddress = "https://timhowland.com"

  /// Falls back rather than force-unwrapping, so a typo in the address above
  /// cannot crash the application on the one launch where a crash is
  /// unrecoverable for the user. The fallback is never reached — a test asserts
  /// the address parses — and deliberately is not a file URL, because
  /// `Scripts/arch-lint.sh` treats that symbol as disk access wherever it
  /// appears (`CON-4`), and the rule is more valuable crude than loosened.
  static var website: URL {
    URL(string: websiteAddress) ?? URL.temporaryDirectory
  }

  static let dismiss = "Start Scratching"
}
