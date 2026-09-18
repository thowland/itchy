import AppKit
import XCTest

/// Regenerates the screenshots in `docs/images` from the running application.
///
/// Not a test of behaviour: it is skipped unless `ITCHY_UI_TEST_ROOT` is set,
/// which only `Scripts/screenshots.sh` does. It lives in the UI suite because
/// XCUITest can capture a window without the Screen Recording permission that
/// `screencapture` would need, and because it drives the real interface, so the
/// pictures show what the application actually draws.
///
/// The test runner is sandboxed and can write neither to the store nor to the
/// repository. So the script owns the store directory and damages it between
/// the two phases, the runner only passes the path on to the application, and
/// each screenshot leaves as an attachment that the script exports from the
/// result bundle.
final class ScreenshotCapture: XCTestCase {
  private var root: String!

  private static let appearance: TimeInterval = 5
  private static let padName = "scratch"

  override func setUpWithError() throws {
    try super.setUpWithError()
    guard let root = ProcessInfo.processInfo.environment["ITCHY_UI_TEST_ROOT"] else {
      throw XCTSkip("Screenshot capture runs only from `make screenshots`.")
    }
    self.root = root
    // Several launches, typing and a rename: longer than a test, and not one.
    executionTimeAllowance = 120
    continueAfterFailure = false
    terminateStrayInstances()
  }

  override func tearDown() {
    terminateStrayInstances()
    super.tearDown()
  }

  /// Phase one: a named, styled pad, then About.
  func testCapturePadAndAbout() {
    capturePad()
    captureAbout()
  }

  /// Phase two, after the script has removed the pad's content: the same pad
  /// opens onto its fault rather than onto an empty editor (specification §6.7).
  func testCaptureFaultedPad() {
    let app = launch()
    XCTAssertTrue(
      app.buttons["Reveal in Finder"].waitForExistence(timeout: Self.appearance),
      "the pad did not open onto its fault")
    attach(app.windows[Self.padName], as: "pad-faulted")
    app.terminate()
  }

  // MARK: - Scenes

  private func capturePad() {
    let app = launch()
    let editor = app.windows.textViews["pad.editor"].firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: Self.appearance), "no pad opened")

    rename(in: app, to: Self.padName)

    editor.click()
    typeBold("Return label", in: editor, app: app)
    editor.typeText("\n1Z 999 AA1 01 2345 6784\n\n")
    typeBold("Invoice 58213", in: editor, app: app)
    editor.typeText("\nRefund held at payments. Ask again on Thursday.\n\n")
    editor.typeText("SELECT id, status FROM refunds WHERE invoice = 58213;")

    let window = app.windows[Self.padName]
    XCTAssertTrue(window.waitForExistence(timeout: Self.appearance), "pad was not renamed")
    attach(window, as: "pad-panel")
    // Terminating goes through applicationShouldTerminate, which saves the pad,
    // so phase two finds it on disk.
    app.terminate()
  }

  private func captureAbout() {
    let app = launch(["-ItchyShowAbout"])
    XCTAssertTrue(
      app.buttons["Close"].waitForExistence(timeout: Self.appearance), "About did not open")
    XCTAssertTrue(app.staticTexts["welcome.version"].exists, "no version line")
    attach(app.windows.firstMatch, as: "welcome")
    app.terminate()
  }

  // MARK: - Driving

  private func launch(_ arguments: [String] = []) -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments = ["-ItchyUITest"] + arguments
    app.launchEnvironment["ITCHY_UI_TEST_ROOT"] = root
    app.launch()
    return app
  }

  private func rename(in app: XCUIApplication, to name: String) {
    let actions = app.windows.menuButtons["pad.actions"]
    XCTAssertTrue(actions.waitForExistence(timeout: Self.appearance))
    actions.click()
    app.menuItems["Pad Settings…"].click()
    let field = app.textFields["pad.settings.name"]
    XCTAssertTrue(field.waitForExistence(timeout: Self.appearance), "Pad Settings did not open")
    field.click()
    field.typeKey(.rightArrow, modifierFlags: .command)
    field.typeKey(.leftArrow, modifierFlags: [.command, .shift])
    field.typeText(name + "\r")
  }

  /// Types a line, makes it bold with the pad's own control, then turns bold off
  /// again so that what follows is not.
  private func typeBold(_ text: String, in editor: XCUIElement, app: XCUIApplication) {
    let bold = app.windows.buttons["pad.format.bold"]
    editor.typeText(text)
    editor.typeKey(.leftArrow, modifierFlags: [.command, .shift])
    bold.click()
    editor.typeKey(.rightArrow, modifierFlags: [])
    bold.click()
  }

  /// Kept with the result bundle, named for the file it becomes.
  private func attach(_ element: XCUIElement, as name: String) {
    // Let the last keystroke and any highlight settle before capturing.
    Thread.sleep(forTimeInterval: 0.5)
    let attachment = XCTAttachment(screenshot: element.screenshot())
    attachment.name = name
    attachment.lifetime = .keepAlways
    add(attachment)
  }

  /// Only builds xcodebuild produced, never an installed copy.
  private func terminateStrayInstances() {
    let running = NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.wdogsystems.itchy")
    for instance in running where instance.bundleURL?.path.contains("/Build/Products/") == true {
      instance.forceTerminate()
    }
  }
}
