import AppKit
import Foundation
import ItchyCore
import Testing

@testable import Itchy

@Suite("First run")
struct FirstRunTests {
  private func settings(seen: Bool) -> AppSettings {
    AppSettings(hasCompletedFirstRun: seen)
  }

  @Test("A fresh install is told where to look")
  func firstLaunch() {
    #expect(
      FirstRunPolicy.shouldShowWelcome(
        settings: settings(seen: false), launchOptions: LaunchOptions()))
  }

  /// `CON-2` prohibits prompts. This is the narrow exception — telling someone
  /// the application exists — and it happens once.
  @Test("It is not shown again once dismissed")
  func secondLaunch() {
    #expect(
      !FirstRunPolicy.shouldShowWelcome(
        settings: settings(seen: true), launchOptions: LaunchOptions()))
  }

  /// A window the suite did not ask for sits in front of the panels it drives,
  /// and the failure looks like a broken application rather than a stray window.
  @Test("It is suppressed under the UI-test flag, even on a fresh store")
  func suppressedUnderTest() {
    let testing = LaunchOptions.parse(["Itchy", LaunchOptions.uiTestFlag])
    #expect(
      !FirstRunPolicy.shouldShowWelcome(settings: settings(seen: false), launchOptions: testing))
  }

  @Test("The flag defaults to not-yet-seen, so a new install gets the window")
  func defaultsToUnseen() {
    #expect(!AppSettings().hasCompletedFirstRun)
  }

  /// The same protection the hotkey fields needed: a settings file written
  /// before this property existed must not fail to decode and take every other
  /// preference down with it.
  @Test("A settings file predating the flag still loads")
  func toleratesOlderSettings() throws {
    let json = """
      {"schemaVersion":1,"padLimit":11,"defaultMode":"plain","launchesAtLogin":true,
       "hotKeyCode":49,"hotKeyModifiers":6144}
      """
    let decoded = try JSONCoding.decoder().decode(AppSettings.self, from: Data(json.utf8))
    #expect(decoded.padLimit == 11)
    #expect(!decoded.hasCompletedFirstRun, "an older install has not seen it")
  }
}

@Suite("Welcome text")
struct WelcomeTextTests {
  /// The one thing the window exists to say.
  @Test("It says the application is run from the menubar")
  func mentionsTheMenubar() {
    let everything = WelcomeText.points.map(\.text).joined(separator: " ")
    #expect(everything.contains("menubar"))
    #expect(everything.contains("no Dock icon"))
  }

  @Test("It covers opening a pad, the hotkey, and not having to save")
  func coversTheBasics() {
    let everything = WelcomeText.points.map(\.text).joined(separator: " ").lowercased()
    #expect(everything.contains("float"))
    #expect(everything.contains("⌃⌥space".lowercased()))
    #expect(everything.contains("saving"))
  }

  @Test("Every point has a symbol and some words")
  func pointsAreComplete() {
    #expect(!WelcomeText.points.isEmpty)
    for point in WelcomeText.points {
      #expect(!point.symbol.isEmpty)
      #expect(!point.text.isEmpty)
    }
  }

  /// A typo in the address must not crash the application on first launch,
  /// which is the one launch where a crash is unrecoverable for the user.
  @Test("The website link is a usable URL")
  func website() {
    #expect(WelcomeText.website.absoluteString == "https://timhowland.com")
    #expect(WelcomeText.website.scheme == "https")
  }

  @Test("The symbols it asks for exist")
  func symbolsResolve() {
    for point in WelcomeText.points {
      #expect(
        NSImage(systemSymbolName: point.symbol, accessibilityDescription: nil) != nil,
        "missing SF Symbol: \(point.symbol)")
    }
  }
}

/// The flow end to end: shown once, dismissal recorded, never shown again.
@MainActor
@Suite("First run through the coordinator")
struct FirstRunIntegrationTests {
  private func makeCoordinator(root: URL) -> PadCoordinator {
    let layout = PadStorageLayout(root: root)
    return PadCoordinator(
      store: PadStore(layout: layout), layout: layout, launchOptions: LaunchOptions())
  }

  private func temporaryRoot() -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-firstrun-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  @Test("A fresh install shows the window, and dismissing it is remembered")
  func showsThenRemembers() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let first = makeCoordinator(root: root)
    await first.start()
    #expect(first.isShowingWelcome, "a fresh install should be told where to look")

    first.dismissWelcome()
    await expect("the window to close") { !first.isShowingWelcome }

    // The preference has to reach disk, or the next launch shows it again.
    let settings = SettingsStore(layout: PadStorageLayout(root: root)).load()
    #expect(settings.hasCompletedFirstRun)

    let second = makeCoordinator(root: root)
    await second.start()
    #expect(!second.isShowingWelcome, "it must not come back")
  }

  /// A window the suite did not ask for would sit in front of the panels it
  /// drives.
  @Test("It never appears under the UI-test flag")
  func suppressedUnderTestFlag() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let layout = PadStorageLayout(root: root)
    let coordinator = PadCoordinator(
      store: PadStore(layout: layout), layout: layout,
      launchOptions: LaunchOptions.parse(["Itchy", LaunchOptions.uiTestFlag]))

    await coordinator.start()

    #expect(!coordinator.isShowingWelcome)
  }
}
