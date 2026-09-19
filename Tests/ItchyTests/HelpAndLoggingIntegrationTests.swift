import AppKit
import ItchyCore
import ItchyServices
import Testing

@testable import Itchy

/// The two ways into help, and the switch that opens and closes the log.
@MainActor
@Suite("Help window and diagnostic logging")
struct HelpAndLoggingIntegrationTests {
  private func makeCoordinator() -> (PadCoordinator, URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-help-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let layout = PadStorageLayout(root: root)
    let coordinator = PadCoordinator(
      store: PadStore(layout: layout), layout: layout, launchOptions: LaunchOptions())
    return (coordinator, root)
  }

  // MARK: - Help

  @Test("Help opens on the book's first topic")
  func opensHelp() {
    let (coordinator, root) = makeCoordinator()
    defer {
      coordinator.closeHelp()
      try? FileManager.default.removeItem(at: root)
    }

    #expect(coordinator.isShowingHelp == false)
    coordinator.showHelp()

    #expect(coordinator.isShowingHelp)
    #expect(coordinator.helpTopic == HelpBook.defaultTopic)
  }

  /// Asking for help twice should not leave two books open on the same subject.
  @Test("Asking again brings the same window forward")
  func doesNotOpenTwice() {
    let (coordinator, root) = makeCoordinator()
    defer {
      coordinator.closeHelp()
      try? FileManager.default.removeItem(at: root)
    }

    coordinator.showHelp()
    coordinator.showHelp()

    #expect(coordinator.isShowingHelp)
    #expect(coordinator.helpTopic == HelpBook.defaultTopic)
  }

  @Test("Asking for a different topic shows that topic")
  func opensOnATopic() {
    let (coordinator, root) = makeCoordinator()
    defer {
      coordinator.closeHelp()
      try? FileManager.default.removeItem(at: root)
    }

    coordinator.showHelp()
    coordinator.showHelp(topic: "agents")

    #expect(coordinator.helpTopic == "agents")
  }

  @Test("Closing it lets the next request open a fresh one")
  func closes() {
    let (coordinator, root) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }

    coordinator.showHelp()
    coordinator.closeHelp()

    #expect(coordinator.isShowingHelp == false)
    #expect(coordinator.helpTopic == nil)
  }

  // MARK: - The log

  @Test("Logging is off until it is switched on, and stops when it is switched off")
  func togglesLogging() throws {
    let (coordinator, root) = makeCoordinator()
    let path = root.appendingPathComponent("itchy-test.log").path
    defer {
      DebugLog.shared.disable()
      try? FileManager.default.removeItem(at: root)
    }

    #expect(coordinator.settings.debugLoggingEnabled == false)
    #expect(coordinator.debugLogPath == nil)

    // The shared log is what the coordinator drives; point it at the scratch
    // directory rather than at /tmp so the suite leaves nothing behind.
    coordinator.settings.debugLoggingEnabled = true
    DebugLog.shared.enable(atPath: path, version: "test")
    #expect(coordinator.debugLogPath == path)

    coordinator.setDebugLoggingEnabled(false)

    #expect(coordinator.settings.debugLoggingEnabled == false)
    #expect(coordinator.debugLogPath == nil)
  }

  /// A backup that decided not to happen is the case the log exists for: four
  /// identical silent returns, until now.
  @Test("An archive that was skipped says which kind of skip it was")
  func archiveOutcomesReachTheLog() throws {
    let (coordinator, root) = makeCoordinator()
    let path = root.appendingPathComponent("archive.log").path
    defer {
      DebugLog.shared.disable()
      try? FileManager.default.removeItem(at: root)
    }
    DebugLog.shared.enable(atPath: path, version: "test")

    coordinator.settings.archiveRetention = 0
    #expect(coordinator.archiveIfNeeded(trigger: .launch) == .disabled)

    coordinator.settings.archiveRetention = 10
    coordinator.settings.lastArchiveAt = Date()
    #expect(coordinator.archiveIfNeeded(trigger: .daily) == .notDue)

    // A fresh store has no pads. That is not a failed backup, and saying so was
    // the first thing the log caught once it was switched on for real.
    coordinator.settings.lastArchiveAt = nil
    #expect(coordinator.archiveIfNeeded(trigger: .launch) == .nothingToArchive)

    DebugLog.shared.disable()
    let contents = try String(contentsOfFile: path, encoding: .utf8)
    #expect(contents.contains("outcome=disabled"))
    #expect(contents.contains("outcome=not due"))
    #expect(contents.contains("outcome=nothing to archive"))
    #expect(contents.contains("outcome=failed") == false)
  }

  /// The caption names the file it is actually writing, rather than the path it
  /// would use by default.
  @Test("The settings caption names the file in use")
  func captionNamesTheFile() {
    #expect(MCPSettingsModel.loggingCaption(path: nil).contains("Off."))
    #expect(MCPSettingsModel.loggingCaption(path: nil).contains("never written"))
    let caption = MCPSettingsModel.loggingCaption(path: "/tmp/somewhere.log")
    #expect(caption.contains("/tmp/somewhere.log"))
    #expect(caption.contains("never the pad's text"))
  }
}

/// Which token store a launch gets.
///
/// This is the seam that keeps the suite off the real Keychain. Opening the
/// real one asks the person running the tests for permission, and a run that
/// waits for an answer hangs — here, and unanswerably on CI.
@Suite("Token store resolution")
struct TokenStoreResolverTests {
  @Test("A launch against a throwaway store never touches the Keychain")
  func throwawayLaunchIsInMemory() {
    let options = LaunchOptions(usesTemporaryStorage: true)
    #expect(TokenStoreResolver.store(for: options) is InMemoryTokenStore)
  }

  /// Stated as a negative on purpose. Naming the Keychain type here would put
  /// the word in a test file, and `arch-lint` forbids that without exception —
  /// the rule is worth more than the slightly more direct assertion.
  @Test("An ordinary launch does not get the in-memory store")
  func ordinaryLaunchIsNotInMemory() {
    #expect(TokenStoreResolver.store(for: LaunchOptions()) is InMemoryTokenStore == false)
  }

  /// The generated-on-first-use behaviour, without a Keychain anywhere near it.
  @Test("A store with nothing in it makes a token once and keeps it")
  func loadOrCreate() throws {
    let store = InMemoryTokenStore()
    #expect(try store.load() == nil)

    let created = try store.loadOrCreate()
    #expect(try store.loadOrCreate() == created)

    try store.delete()
    #expect(try store.load() == nil)
    #expect(try store.loadOrCreate() != created)
  }
}
