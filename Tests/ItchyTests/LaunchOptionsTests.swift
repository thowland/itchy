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

  @Test("The storage root moves with the flag")
  func storageRootFollows() {
    let testing = AppStorage.layout(options: LaunchOptions(usesTemporaryStorage: true))
    let real = AppStorage.layout(options: LaunchOptions(usesTemporaryStorage: false))
    #expect(testing.root.path != real.root.path)
    #expect(testing.root.deletingLastPathComponent().lastPathComponent == "ItchyUITests")
    #expect(testing.root.lastPathComponent == AppStorage.uiTestRun, "one directory per launch")
  }
}
