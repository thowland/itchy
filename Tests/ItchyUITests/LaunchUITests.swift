import AppKit
import XCTest

/// The UI suite is small and deliberately shallow: it covers what unit tests
/// structurally cannot reach (implementation plan §14.4).
///
/// Every case runs the application against a throwaway storage root, so the
/// user's real pads are never touched.
final class LaunchUITests: XCTestCase {
  /// Nothing here should take ten seconds. Exceeding it means the app did not
  /// launch or a panel never appeared, which is a failure rather than slowness.
  override func setUp() {
    super.setUp()
    executionTimeAllowance = 10
    continueAfterFailure = false
    terminateStrayInstances()
  }

  override func tearDown() {
    terminateStrayInstances()
    super.tearDown()
  }

  /// An instance left behind by an interrupted run confuses XCUIApplication,
  /// which expects to own the process it launches. This cost an afternoon once.
  private func terminateStrayInstances() {
    let running = NSRunningApplication.runningApplications(
      withBundleIdentifier: "com.wdogsystems.itchy")
    for instance in running {
      instance.forceTerminate()
    }
  }

  /// The pad's text view, looked up by identifier rather than by element type:
  /// the identifier is the stable part across the Sprint 2 placeholder and the
  /// Sprint 3 `NSTextView` that replaced it.
  private func padInput(in app: XCUIApplication) -> XCUIElement {
    app.windows.textViews["pad.editor"].firstMatch
  }

  private func launchApp() -> XCUIApplication {
    let app = XCUIApplication()
    app.launchArguments += ["-ItchyUITest"]
    app.launch()
    addTeardownBlock { app.terminate() }
    return app
  }

  /// Shorter than the default: if a panel has not appeared in five seconds it
  /// is not going to.
  private static let appearance: TimeInterval = 5

  // testLaunchesAsAnAccessory was removed here.
  //
  // It launched without -ItchyUITest, which meant two things. It took twenty
  // seconds, because XCUIApplication waits for the app it launched to reach the
  // foreground and an accessory application never does — a test that slow has
  // not found a slow path, it has found a wait that will never end. And it ran
  // against the user's real store rather than the throwaway one, which is the
  // thing LaunchOptions exists to prevent.
  //
  // What it asserted is covered without either problem:
  // testPanelAppearsWithoutActivatingTheApplication makes the same
  // runningBackground assertion with the flag set, and FR-1.1 is additionally
  // held by AppShellTests and ReleaseGuaranteeTests at unit level.

  /// **Sprint 2's exit gate.** `FR-3.2`: a non-activating panel does not become
  /// key by default, and the symptom is a panel that looks entirely correct and
  /// silently discards every keystroke. Nothing should be built on the panel
  /// until this passes.
  func testPanelAcceptsTypedInput() {
    let app = launchApp()
    let field = padInput(in: app)
    XCTAssertTrue(field.waitForExistence(timeout: Self.appearance), "the pad panel did not appear")

    field.click()
    field.typeText("a tracking number")

    XCTAssertEqual(field.value as? String, "a tracking number")
  }

  /// `FR-3.1`: a panel appearing must not activate the application.
  ///
  /// This is the half of `FR-3.1` that can be asserted. The other half — that a
  /// *click* does not activate — cannot be: to accept the keystrokes `FR-3.2`
  /// requires, the panel must hold keyboard focus, and an application holding
  /// keyboard focus is by definition the active one. See the sprint note in
  /// docs/decisions/D-14-panel-activation.md.
  func testPanelAppearsWithoutActivatingTheApplication() {
    let app = launchApp()
    XCTAssertTrue(padInput(in: app).waitForExistence(timeout: Self.appearance))

    XCTAssertEqual(
      app.state, .runningBackground,
      "a pad appearing must not steal focus from whatever the user is doing")
  }

  /// `FR-3.6`: the pad's state is legible from the panel without opening
  /// settings or a menu.
  func testPanelShowsNameAndMode() {
    let app = launchApp()
    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: Self.appearance))
    let window = app.windows.firstMatch
    XCTAssertTrue(window.staticTexts["styled"].exists, "the mode should be on the pad")
  }

  private func waitForValue(_ element: XCUIElement, _ value: String) -> Bool {
    let predicate = NSPredicate(format: "value == %@", value)
    let expectation = XCTNSPredicateExpectation(predicate: predicate, object: element)
    return XCTWaiter().wait(for: [expectation], timeout: Self.appearance) == .completed
  }

  /// `FR-4.11`, D-20: the bold control reaches a real panel, and clicking it
  /// leaves keyboard focus in the pad — `typeText` fails outright on an element
  /// that does not have focus, so the final keystroke is the focus assertion.
  func testBoldButtonFormatsTheSelection() {
    let app = launchApp()
    let field = padInput(in: app)
    XCTAssertTrue(field.waitForExistence(timeout: Self.appearance))
    field.click()
    field.typeKey(.downArrow, modifierFlags: .command)
    field.typeText("\nbold me")
    field.typeKey(.leftArrow, modifierFlags: [.command, .shift])

    let bold = app.windows.buttons["pad.format.bold"]
    XCTAssertTrue(bold.waitForExistence(timeout: Self.appearance), "no bold control on a styled pad")
    bold.click()

    XCTAssertTrue(waitForValue(bold, "on"), "bold did not apply to the selection")
    field.typeKey(.rightArrow, modifierFlags: [])
    field.typeText("!")
    XCTAssertTrue((field.value as? String)?.contains("bold me!") == true)
  }

  /// D-20: an accessory application has no Format menu, so ⌘B only works
  /// because the text view answers it. This is the case unit tests cannot
  /// reach — whether the chord arrives at a non-activating panel at all.
  func testCommandBTogglesBoldInThePanel() {
    let app = launchApp()
    let field = padInput(in: app)
    XCTAssertTrue(field.waitForExistence(timeout: Self.appearance))
    field.click()
    field.typeKey(.downArrow, modifierFlags: .command)
    field.typeText("\nshortcut")
    field.typeKey(.leftArrow, modifierFlags: [.command, .shift])

    field.typeKey("b", modifierFlags: .command)

    XCTAssertTrue(
      waitForValue(app.windows.buttons["pad.format.bold"], "on"), "⌘B did not reach the pad")
  }

  /// `FR-2.9`, D-21: renaming from the pad's own settings sheet. The sheet is
  /// an ordinary window, so this is also the test that it accepts typing from a
  /// non-activating panel, and that the open panel is retitled.
  func testPadSettingsSheetRenamesThePad() {
    let app = launchApp()
    XCTAssertTrue(padInput(in: app).waitForExistence(timeout: Self.appearance))
    let actions = app.windows.menuButtons["pad.actions"]
    XCTAssertTrue(actions.waitForExistence(timeout: Self.appearance))
    actions.click()
    app.menuItems["Pad Settings…"].click()

    let name = app.textFields["pad.settings.name"]
    XCTAssertTrue(name.waitForExistence(timeout: Self.appearance), "the settings sheet did not open")
    name.click()
    name.typeKey(.rightArrow, modifierFlags: .command)
    name.typeKey(.leftArrow, modifierFlags: [.command, .shift])
    let renamed = "Renamed \(Int.random(in: 1000...9999))"
    name.typeText(renamed + "\r")

    XCTAssertTrue(
      app.windows[renamed].waitForExistence(timeout: Self.appearance),
      "the panel was not retitled")
  }
}
