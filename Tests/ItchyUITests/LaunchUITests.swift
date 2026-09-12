import XCTest

/// XCUITest is present from Sprint 0 so that the harness is proven before
/// Sprint 2 needs it for the test that matters — a panel summoned over a
/// fullscreen application accepting typed input (FR-3.2).
final class LaunchUITests: XCTestCase {
  func testLaunchesAsAnAccessoryWithoutAWindow() {
    let app = XCUIApplication()
    app.launch()

    // FR-1.1: an accessory application runs without ever becoming the
    // foreground application. `runningForeground` here would mean LSUIElement
    // was not taking effect.
    XCTAssertEqual(app.state, .runningBackground)
    XCTAssertNotEqual(app.state, .notRunning)

    // And it shows no window of its own; the menubar is the only surface.
    XCTAssertEqual(app.windows.count, 0)
  }
}
