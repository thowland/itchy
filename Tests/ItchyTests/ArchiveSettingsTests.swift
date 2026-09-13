import Foundation
import ItchyCore
import Testing

@testable import Itchy

@Suite("Backup settings wording")
struct ArchiveSettingsTextTests {
  /// The privacy cost is stated rather than left to be worked out: a backup
  /// holds copies of pads the user has since deleted.
  @Test("The caption says copies include deleted pads, and how to keep none")
  func caption() {
    let caption = ArchiveSettingsText.retentionCaption(10)
    #expect(caption.contains("deleted"))
    #expect(caption.contains("zero"))
  }

  @Test("Turning it off says plainly that nothing can be recovered")
  func offCaption() {
    let caption = ArchiveSettingsText.retentionCaption(ArchiveBounds.disabled)
    #expect(caption.contains("No copies"))
    #expect(caption.contains("recovered"))
  }

  @Test("The label reads as off rather than as zero backups")
  func label() {
    #expect(ArchiveSettingsText.retentionLabel(ArchiveBounds.disabled) == "Backups: off")
    #expect(ArchiveSettingsText.retentionLabel(5) == "Backups to keep: 5")
  }

  @Test(
    "Sizes stay coarse",
    arguments: [
      (bytes: 0, expected: "None"),
      (bytes: 500, expected: "under 1 MB"),
      (bytes: 40 * 1_048_576, expected: "40 MB"),
    ])
  func summaries(bytes: Int, expected: String) {
    let count = bytes == 0 ? 0 : 2
    let summary = ArchiveSettingsText.summary(count: count, bytes: bytes)
    #expect(summary.contains(expected))
  }

  @Test("One backup is singular")
  func singular() {
    #expect(ArchiveSettingsText.summary(count: 1, bytes: 2_000_000).contains("1 backup,"))
    #expect(ArchiveSettingsText.summary(count: 3, bytes: 2_000_000).contains("3 backups,"))
  }
}

/// The flow through the coordinator: archived on launch, pruned to the limit,
/// and genuinely off when set to zero.
@MainActor
@Suite("Archiving through the coordinator")
struct ArchiveIntegrationTests {
  private func temporaryRoot() -> URL {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-archive-\(UUID().uuidString)")
    try? FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
    return root
  }

  private func coordinator(root: URL) -> PadCoordinator {
    let layout = PadStorageLayout(root: root)
    return PadCoordinator(
      store: PadStore(layout: layout), layout: layout, launchOptions: LaunchOptions())
  }

  private func seedPads(_ count: Int, root: URL) async throws {
    let store = PadStore(layout: PadStorageLayout(root: root))
    await store.load()
    for index in 0..<count {
      let pad = try await store.createPad(name: "pad \(index)")
      await store.stage(PadContent.plainText("content \(index)"), for: pad.id, origin: .user)
    }
    try await store.flushAll()
  }

  @Test("Launching archives the pads that are there")
  func archivesOnLaunch() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try await seedPads(2, root: root)

    let coordinator = coordinator(root: root)
    await coordinator.start()

    #expect(coordinator.archives.count == 1)
    #expect(coordinator.archives.first?.padCount == 2)
  }

  /// Without the fingerprint check, launch and quit take two identical copies
  /// and a day of restarts pushes the useful one off the end.
  @Test("An unchanged store is not archived twice")
  func skipsWhenUnchanged() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try await seedPads(1, root: root)

    let coordinator = coordinator(root: root)
    await coordinator.start()
    coordinator.archiveIfNeeded(trigger: .quit)
    coordinator.archiveIfNeeded(trigger: .launch)

    #expect(coordinator.archives.count == 1)
  }

  @Test("Zero retention takes no backups at all")
  func disabled() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try await seedPads(1, root: root)

    let coordinator = coordinator(root: root)
    coordinator.settings.archiveRetention = ArchiveBounds.disabled
    coordinator.archiveIfNeeded(trigger: .launch)

    #expect(coordinator.archives.isEmpty)
  }

  @Test("Lowering the retention prunes immediately")
  func loweringPrunes() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try await seedPads(1, root: root)
    let coordinator = coordinator(root: root)
    await coordinator.start()

    for hour in 1...4 {
      coordinator.settings.lastArchiveFingerprint = "forced-\(hour)"
      coordinator.archiveIfNeeded(
        trigger: .launch, now: Date().addingTimeInterval(Double(hour) * 3_600))
    }
    #expect(coordinator.archives.count > 2)

    coordinator.setArchiveRetention(2)

    #expect(coordinator.archives.count == 2)
  }

  @Test("Deleting all backups leaves none, and forgets it ever took one")
  func removeAll() async throws {
    let root = temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    try await seedPads(1, root: root)
    let coordinator = coordinator(root: root)
    await coordinator.start()
    #expect(!coordinator.archives.isEmpty)

    coordinator.removeAllArchives()

    #expect(coordinator.archives.isEmpty)
    #expect(coordinator.settings.lastArchiveAt == nil)
  }
}
