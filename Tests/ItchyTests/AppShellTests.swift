import XCTest

@testable import Itchy

/// XCTest is present from Sprint 0 so that the harness is proven rather than
/// assumed (D-3). Swift Testing carries the package suites; this target exists
/// for the cases that need XCTest machinery and for host-application tests.
final class AppShellTests: XCTestCase {
  func testActivationPolicyIsAccessory() {
    // FR-1.1: the app runs as an accessory with no Dock icon. LSUIElement in
    // Info.plist is the mechanism; AppDelegate asserts it again at launch.
    AppDelegate().applicationDidFinishLaunching(
      Notification(name: NSApplication.didFinishLaunchingNotification))
    XCTAssertEqual(NSApp.activationPolicy(), .accessory)
  }

  func testBundleDeclaresAccessoryMode() {
    let bundle = Bundle(for: AppDelegate.self)
    XCTAssertEqual(bundle.object(forInfoDictionaryKey: "LSUIElement") as? Bool, true)
  }
}
