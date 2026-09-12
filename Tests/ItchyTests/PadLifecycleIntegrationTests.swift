import AppKit
import ItchyCore
import Testing

@testable import Itchy

/// Sprint 4's new ground: the lifecycle operations as the interface actually
/// drives them, and the faulted-pad rule end to end.
@MainActor
@Suite("Pad lifecycle through the coordinator")
struct PadLifecycleIntegrationTests {
  private func makeCoordinator() -> (PadCoordinator, URL) {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-lifecycle-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    let layout = PadStorageLayout(root: root)
    let coordinator = PadCoordinator(
      store: PadStore(layout: layout), layout: layout, launchOptions: LaunchOptions())
    return (coordinator, root)
  }

  /// Waits for the coordinator's fire-and-forget work to settle.
  ///
  /// Its mutators return immediately so the interface never blocks; tests need
  /// the state that follows. Failing at the boundary rather than returning
  /// quietly means a hang reports itself instead of surfacing as whichever
  /// assertion runs next (`TestTiming`).
  private func settle(
    _ coordinator: PadCoordinator,
    until condition: @escaping @MainActor () -> Bool,
    sourceLocation: SourceLocation = #_sourceLocation
  ) async {
    await expect(
      "the coordinator to reach the expected state",
      toBecomeTrue: condition, sourceLocation: sourceLocation)
  }

  @Test("A created pad takes the configured default mode (FR-2.8)")
  func defaultMode() async throws {
    let (coordinator, root) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }
    await coordinator.start()

    coordinator.setDefaultMode(.plain)
    coordinator.createPad()
    await settle(coordinator) { coordinator.pads.count == 1 }
    await settle(coordinator) { coordinator.pads.first?.mode == .plain }

    #expect(coordinator.pads.first?.mode == .plain)
  }

  @Test("Renaming is immediate and persists (FR-2.4)")
  func rename() async throws {
    let (coordinator, root) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }
    await coordinator.start()
    coordinator.createPad()
    await settle(coordinator) { coordinator.pads.count == 1 }
    let pad = try #require(coordinator.pads.first)

    coordinator.rename(pad.id, to: "renamed")
    await settle(coordinator) { coordinator.pads.first?.name == "renamed" }

    #expect(coordinator.pads.first?.name == "renamed")
    #expect(coordinator.rows.first?.name == "renamed", "FR-1.2: the menu follows")
  }

  /// `FR-2.7`: a pinned pad's panel is present after relaunch.
  @Test("A pinned pad reopens at launch and an unpinned one does not")
  func pinnedReopen() async throws {
    let (coordinator, root) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }
    await coordinator.start()
    coordinator.createPad()
    coordinator.createPad()
    await settle(coordinator) { coordinator.pads.count == 2 }
    let pinned = try #require(coordinator.pads.first)
    coordinator.setPinned(pinned.id, true)
    await settle(coordinator) { coordinator.pads.first?.isPinned == true }

    let layout = PadStorageLayout(root: root)
    let relaunched = PadCoordinator(
      store: PadStore(layout: layout), layout: layout, launchOptions: LaunchOptions())
    await relaunched.start()

    #expect(relaunched.openPanelCount == 1, "only the pinned pad reopens")
  }

  /// `FR-2.2`: lowering the limit never deletes or hides content.
  @Test("Lowering the pad limit leaves every pad listed")
  func loweringLimit() async throws {
    let (coordinator, root) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }
    await coordinator.start()
    for _ in 0..<3 { coordinator.createPad() }
    await settle(coordinator) { coordinator.pads.count == 3 }

    coordinator.setPadLimit(1)
    await settle(coordinator) { coordinator.settings.padLimit == 1 }

    #expect(coordinator.pads.count == 3)
    #expect(coordinator.rows.count == 3)
  }

  @Test("The pad limit survives a relaunch and is clamped on the way in")
  func limitPersists() async throws {
    let (coordinator, root) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }
    await coordinator.start()
    coordinator.setPadLimit(999)

    let layout = PadStorageLayout(root: root)
    let relaunched = PadCoordinator(
      store: PadStore(layout: layout), layout: layout, launchOptions: LaunchOptions())
    await relaunched.start()

    #expect(relaunched.settings.padLimit == PadBounds.hardCeiling)
  }

  @Test("Deleting removes the pad and its directory (FR-2.6)")
  func deletion() async throws {
    let (coordinator, root) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }
    await coordinator.start()
    coordinator.createPad()
    await settle(coordinator) { coordinator.pads.count == 1 }
    let pad = try #require(coordinator.pads.first)
    let directory = PadStorageLayout(root: root).directory(for: pad.id)

    coordinator.deletePad(pad.id)
    await settle(coordinator) { coordinator.pads.isEmpty }

    #expect(coordinator.pads.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: directory.path))
  }

  /// `FR-4.9`: copying a pad's contents as plain text is a single action.
  @Test("Copying a pad puts its plain text on the pasteboard")
  func copyAsPlainText() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-copy-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let layout = PadStorageLayout(root: root)

    // Content is written and flushed before the coordinator exists, which is
    // what a relaunch looks like. Two PadStore instances over one directory do
    // not share a cache — by design, since the store is the single writer — so a
    // test that wrote through a second store would be asserting against state
    // the coordinator has no reason to see.
    let seed = PadStore(layout: layout)
    await seed.load()
    let pad = try await seed.createPad(name: "outbound")
    await seed.stage(PadContent.plainText("copy me out"), for: pad.id, origin: .user)
    try await seed.flushAll()

    let coordinator = PadCoordinator(
      store: PadStore(layout: layout), layout: layout, launchOptions: LaunchOptions())
    await coordinator.start()

    NSPasteboard.general.clearContents()
    coordinator.copyAsPlainText(pad.id)
    await settle(coordinator) { NSPasteboard.general.string(forType: .string) == "copy me out" }

    #expect(NSPasteboard.general.string(forType: .string) == "copy me out")
  }

  /// **Specification §6.7.** The rule this sprint's exit depends on: a pad whose
  /// content cannot be read is listed and selectable, and opens onto the fault —
  /// never onto an empty editor, which the next save would turn into data loss.
  @Test("A pad with unreadable content never presents an editable empty editor")
  func faultedPadIsNotAnEditor() async throws {
    let (coordinator, root) = makeCoordinator()
    defer { try? FileManager.default.removeItem(at: root) }
    await coordinator.start()
    coordinator.createPad()
    await settle(coordinator) { coordinator.pads.count == 1 }
    let pad = try #require(coordinator.pads.first)

    let layout = PadStorageLayout(root: root)
    let store = PadStore(layout: layout)
    await store.load()
    await store.stage(PadContent.plainText("precious"), for: pad.id, origin: .user)
    try await store.flushAll()
    try FileManager.default.removeItem(at: layout.contentDirectory(for: pad.id))

    let relaunched = PadCoordinator(
      store: PadStore(layout: layout), layout: layout, launchOptions: LaunchOptions())
    await relaunched.start()

    #expect(relaunched.pads.count == 1, "the pad is still listed")
    #expect(relaunched.rows.first?.isFaulted == true, "and marked in the menu")

    let fault = try #require(await relaunched.fault(for: pad.id))
    #expect(!FaultPresentation.allowsEditing(fault), "it must not open as an editor")
  }
}
