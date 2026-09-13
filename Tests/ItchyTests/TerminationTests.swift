import AppKit
import Foundation
import ItchyCore
import Testing

@testable import Itchy

/// `FR-5.5` and D-18 at quit: the last edit is saved, and the backup taken
/// afterwards holds it.
@MainActor
@Suite("Termination")
struct TerminationTests {
  private func temporaryRoot() -> URL {
    URL.temporaryDirectory.appendingPathComponent("itchy-termination-\(UUID().uuidString)")
  }

  /// Text typed inside the serialisation debounce exists only in the text view.
  /// The previous quit path blocked the main thread while waiting for a save
  /// that needed the main thread, so this edit could never land.
  @Test("An edit made just before quitting is saved, and the quit backup holds it")
  func savesThenArchives() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let layout = PadStorageLayout(root: root)
    let store = PadStore(layout: layout)
    await store.load()
    let pad = try await store.createPad(name: "scratch")
    try await store.flushAll()
    let coordinator = PadCoordinator(store: store, layout: layout, launchOptions: LaunchOptions())
    coordinator.settings.lastArchiveFingerprint = ArchiveStore(layout: layout).fingerprint()

    let editor = PadTextCoordinator(padID: pad.id, store: store)
    let textView = PadTextView()
    textView.configure(for: .styled)
    editor.attach(textView)
    coordinator.editors[pad.id] = editor
    textView.textStorage?.setAttributedString(NSAttributedString(string: "typed at the last moment"))

    await coordinator.prepareForTermination()

    let reloaded = PadStore(layout: layout)
    await reloaded.load()
    #expect(try await reloaded.content(of: pad.id).plainText == "typed at the last moment")
    #expect(coordinator.archives.count == 1, "the change should have been archived at quit")
  }

  @Test("Quitting with nothing changed takes no backup")
  func unchanged() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let layout = PadStorageLayout(root: root)
    let store = PadStore(layout: layout)
    await store.load()
    _ = try await store.createPad(name: "scratch")
    try await store.flushAll()
    let coordinator = PadCoordinator(store: store, layout: layout, launchOptions: LaunchOptions())
    coordinator.settings.lastArchiveFingerprint = ArchiveStore(layout: layout).fingerprint()

    await coordinator.prepareForTermination()

    #expect(coordinator.archives.isEmpty)
  }

  @Test("A save that finishes in time is reported as completed")
  func completes() async {
    let outcome = await TerminationFlush.run(limit: .seconds(2)) {}
    #expect(outcome == .completed)
  }

  /// A hung write must not stop Itchy from quitting.
  @Test("A save that outlasts the limit is reported as timed out")
  func timesOut() async {
    let outcome = await TerminationFlush.run(limit: .milliseconds(50)) {
      try? await Task.sleep(for: .milliseconds(500))
    }
    #expect(outcome == .timedOut)
  }
}
