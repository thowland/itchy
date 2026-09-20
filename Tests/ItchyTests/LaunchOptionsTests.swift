import Testing

@testable import Itchy

@Suite("Launch options")
struct LaunchOptionsTests {
  @Test("An ordinary launch opens nothing and uses the real store")
  func ordinaryLaunch() {
    let options = LaunchOptions.parse(["/usr/bin/Itchy"])
    #expect(!options.opensPadOnLaunch)
    #expect(!options.usesTemporaryStorage)
  }

  /// A UI test that wrote to the real store would create and delete the user's
  /// pads, so the flag has to move the storage root as well as open a panel.
  @Test("The UI-test flag opens a pad and redirects storage")
  func uiTestLaunch() {
    let options = LaunchOptions.parse(["/usr/bin/Itchy", LaunchOptions.uiTestFlag])
    #expect(options.opensPadOnLaunch)
    #expect(options.usesTemporaryStorage)
  }

  @Test("The flag is recognised wherever it appears")
  func positionIndependent() {
    let options = LaunchOptions.parse(["x", LaunchOptions.uiTestFlag, "y"])
    #expect(options.opensPadOnLaunch)
  }

  @Test("The About flag shows About instead of opening a pad")
  func aboutLaunch() {
    let options = LaunchOptions.parse([
      "x", LaunchOptions.uiTestFlag, LaunchOptions.showAboutFlag,
    ])
    #expect(options.showsAboutOnLaunch)
    #expect(!options.opensPadOnLaunch)
    #expect(options.usesTemporaryStorage)
  }

  @Test("A storage root from the environment is used under the UI-test flag")
  func chosenRoot() {
    let options = LaunchOptions.parse(
      ["x", LaunchOptions.uiTestFlag],
      environment: [LaunchOptions.storageRootVariable: "/tmp/itchy-chosen"])
    #expect(options.storageRoot == "/tmp/itchy-chosen")
    #expect(AppStorage.layout(options: options).root.path == "/tmp/itchy-chosen")
  }

  /// Nothing in the environment may point a real launch at another store, and
  /// the About flag alone must not change an ordinary launch.
  @Test("Without the UI-test flag, the root and the About flag are ignored")
  func ignoredOutsideTests() {
    let options = LaunchOptions.parse(
      ["x", LaunchOptions.showAboutFlag],
      environment: [LaunchOptions.storageRootVariable: "/tmp/itchy-chosen"])
    #expect(options == LaunchOptions())
  }

  @Test("The storage root moves with the flag")
  func storageRootFollows() {
    let testing = AppStorage.layout(options: LaunchOptions(usesTemporaryStorage: true))
    let real = AppStorage.layout(options: LaunchOptions(usesTemporaryStorage: false))
    #expect(testing.root.path != real.root.path)
    #expect(testing.root.deletingLastPathComponent().lastPathComponent == "ItchyUITests")
    #expect(testing.root.lastPathComponent == AppStorage.uiTestRun, "one directory per launch")
  }

  /// The screenshot capture opens Settings and Help directly rather than
  /// driving a menubar extra, which XCUITest cannot reach.
  @Test("The screenshot flags open Settings and Help over a pad")
  func screenshotWindowFlags() {
    let settings = LaunchOptions.parse([
      LaunchOptions.uiTestFlag, LaunchOptions.showSettingsFlag,
    ])
    #expect(settings.showsSettingsOnLaunch)
    #expect(settings.opensPadOnLaunch, "Settings reads better over a pad")
    #expect(settings.showsHelpOnLaunch == false)

    let help = LaunchOptions.parse([LaunchOptions.uiTestFlag, LaunchOptions.showHelpFlag])
    #expect(help.showsHelpOnLaunch)
    #expect(help.opensPadOnLaunch)
  }

  /// The same rule the storage root has: nothing in the arguments opens a
  /// window on an ordinary launch.
  @Test("Without the UI-test flag the window flags do nothing")
  func windowFlagsNeedTheTestFlag() {
    let options = LaunchOptions.parse([
      LaunchOptions.showSettingsFlag, LaunchOptions.showHelpFlag,
      LaunchOptions.showAboutFlag,
    ])
    #expect(options == LaunchOptions())
    #expect(options.showsSettingsOnLaunch == false)
    #expect(options.showsHelpOnLaunch == false)
  }
}
