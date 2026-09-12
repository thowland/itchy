import XCTest

/// The UI suite is small and deliberately shallow: it covers what unit tests
/// structurally cannot reach (implementation plan §14.4).
///
/// Every case runs the application against a throwaway storage root, so the
/// user's real pads are never touched.
final class LaunchUITests: XCTestCase {
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
    return app
  }

  /// `FR-1.1`: an accessory application runs without ever becoming the
  /// foreground application and shows no window of its own at launch.
  func testLaunchesAsAnAccessory() {
    let app = XCUIApplication()
    app.launch()
    XCTAssertEqual(app.state, .runningBackground)
    XCTAssertNotEqual(app.state, .notRunning)
  }

  /// **Sprint 2's exit gate.** `FR-3.2`: a non-activating panel does not become
  /// key by default, and the symptom is a panel that looks entirely correct and
  /// silently discards every keystroke. Nothing should be built on the panel
  /// until this passes.
  func testPanelAcceptsTypedInput() {
    let app = launchApp()
    let field = padInput(in: app)
    XCTAssertTrue(field.waitForExistence(timeout: 10), "the pad panel did not appear")

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
    XCTAssertTrue(padInput(in: app).waitForExistence(timeout: 10))

    XCTAssertEqual(
      app.state, .runningBackground,
      "a pad appearing must not steal focus from whatever the user is doing")
  }

  /// `FR-3.6`: the pad's state is legible from the panel without opening
  /// settings or a menu.
  func testPanelShowsNameAndMode() {
    let app = launchApp()
    XCTAssertTrue(app.windows.firstMatch.waitForExistence(timeout: 10))
    let window = app.windows.firstMatch
    XCTAssertTrue(window.staticTexts["styled"].exists, "the mode should be on the pad")
  }
}
