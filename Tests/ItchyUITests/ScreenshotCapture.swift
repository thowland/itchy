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

  /// Phase two: the parts somebody reads the README to understand — what can be
  /// done to a pad, where the model goes, how an agent is let in, and the help.
  ///
  /// It runs before the store is damaged, because three of the four want a pad
  /// that still opens.
  func testCaptureTransformsAndSettings() {
    captureTransformMenu()
    captureSettings(tab: "models", as: "settings-models")
    captureSettings(tab: "agents", as: "settings-agents")
    captureHelp()
  }

  /// Phase three, after the script has removed the pad's content: the same pad
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

    focus(editor, in: app)
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
    // The tagline rather than the version line. The version carries
    // `textSelection(.enabled)`, and a selectable Text is not reliably exposed
    // under its accessibility identifier — the check was policing how SwiftUI
    // renders one rather than whether About drew. This asserts the same thing
    // about an element that is plainly a label.
    XCTAssertTrue(
      app.staticTexts["A scratchpad that lives in your menubar."]
        .waitForExistence(timeout: Self.appearance),
      "About opened without its contents")
    attach(app.windows.firstMatch, as: "welcome")
    app.terminate()
  }

  /// The wand menu, open.
  ///
  /// The menu is its own window rather than part of the pad's, so the capture
  /// is of the menu element. The script seeds a model into the store first, so
  /// the model-backed transforms sit in the list underneath the deterministic
  /// ones, which is the arrangement `FR-9.6` requires and the thing worth
  /// showing.
  private func captureTransformMenu() {
    let app = launch()
    let editor = app.windows.textViews["pad.editor"].firstMatch
    XCTAssertTrue(editor.waitForExistence(timeout: Self.appearance), "no pad opened")

    let transforms = app.windows.menuButtons["pad.transforms"]
    XCTAssertTrue(transforms.waitForExistence(timeout: Self.appearance), "no transform menu")
    transforms.click()

    XCTAssertTrue(
      app.menus.firstMatch.waitForExistence(timeout: Self.appearance),
      "the menu did not open")
    // The one with a frame. `app.menus` also answers with an off-screen
    // placeholder whose frame is empty, and asking that for a screenshot fails
    // with a complaint about the frame rather than about the menu.
    let menu = largestMenu(in: app)
    XCTAssertNotNil(menu, "no open menu had a frame to capture")
    attach(menu ?? app.menus.firstMatch, as: "transform-menu")

    // Closed before terminating, or the menu tracking loop holds the run.
    app.typeKey(.escape, modifierFlags: [])
    app.terminate()
  }

  /// The open menu, as opposed to whatever else answers to `menus`.
  private func largestMenu(in app: XCUIApplication) -> XCUIElement? {
    var best: XCUIElement?
    var bestArea: CGFloat = 0
    for index in 0..<app.menus.count {
      let candidate = app.menus.element(boundBy: index)
      guard candidate.exists else { continue }
      let area = candidate.frame.width * candidate.frame.height
      guard area > bestArea else { continue }
      best = candidate
      bestArea = area
    }
    return bestArea > 0 ? best : nil
  }

  /// The window is opened at the section rather than clicked to it.
  ///
  /// A `TabView`'s tabs are not reliably exposed to the accessibility tree —
  /// not as radio buttons, not as buttons, not under a label — so driving them
  /// meant guessing at a shape that changes between macOS versions. Naming the
  /// section at launch is deterministic, and it left the settings window able
  /// to open at a section, which is worth having anyway.
  private func captureSettings(tab: String, as name: String) {
    let app = XCUIApplication()
    app.launchArguments = ["-ItchyUITest", "-ItchyShowSettings"]
    app.launchEnvironment["ITCHY_UI_TEST_ROOT"] = root
    app.launchEnvironment["ITCHY_SETTINGS_TAB"] = tab
    app.launch()

    let window = app.windows["Itchy Settings"].firstMatch
    XCTAssertTrue(window.waitForExistence(timeout: Self.appearance), "Settings did not open")
    Thread.sleep(forTimeInterval: 0.6)
    attach(window, as: name)
    app.terminate()
  }

  private func captureHelp() {
    let app = launch(["-ItchyShowHelp"])
    let window = app.windows["Itchy Help"].firstMatch
    XCTAssertTrue(window.waitForExistence(timeout: Self.appearance), "Help did not open")
    // The models topic, since that is where the README sends people.
    let topic = window.descendants(matching: .any)["help.topic.models"].firstMatch
    if topic.waitForExistence(timeout: Self.appearance) {
      topic.click()
    }
    attach(window, as: "help")
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
    field.typeText(name)
    // Dismissed by its own button rather than by Return. The field's onSubmit
    // applies the name and leaves the sheet standing, so a Return here renames
    // the pad and then blocks everything that follows behind a modal sheet.
    let done = app.buttons["pad.settings.done"]
    XCTAssertTrue(done.waitForExistence(timeout: Self.appearance), "no Done button")
    done.click()
    XCTAssertTrue(
      field.waitForNonExistence(timeout: Self.appearance),
      "the pad settings sheet did not close")
  }

  /// Puts the keyboard into the editor, and waits until it is actually there.
  ///
  /// A pad panel appears without activating Itchy (D-14), so after the rename
  /// sheet closes the application is often not frontmost and a click on the
  /// editor moves the caret without taking key focus. Typing then fails with
  /// "neither element nor any descendant has keyboard focus", which is the
  /// right complaint about the wrong thing — the click worked, the activation
  /// did not.
  private func focus(_ editor: XCUIElement, in app: XCUIApplication) {
    app.activate()
    editor.click()
    Thread.sleep(forTimeInterval: 0.5)
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
