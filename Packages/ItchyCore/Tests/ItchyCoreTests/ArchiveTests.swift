import Foundation
import Testing

@testable import ItchyCore

@Suite("Archive policy")
struct ArchivePolicyTests {
  private let now = Date(timeIntervalSince1970: 1_789_000_000)

  /// Zero retention is the answer for a user who would rather no copies of
  /// deleted pads existed. It has to actually mean off.
  @Test("Retention of zero disables archiving entirely", arguments: ArchiveTrigger.allCases)
  func disabled(trigger: ArchiveTrigger) {
    #expect(
      !ArchivePolicy.shouldArchive(
        trigger: trigger, retention: 0, lastArchive: nil, now: now))
  }

  @Test("Launch and quit always archive", arguments: [ArchiveTrigger.launch, .quit])
  func launchAndQuit(trigger: ArchiveTrigger) {
    #expect(
      ArchivePolicy.shouldArchive(trigger: trigger, retention: 10, lastArchive: now, now: now))
  }

  @Test("The daily archive waits a day")
  func daily() {
    let yesterday = now.addingTimeInterval(-25 * 60 * 60)
    let anHourAgo = now.addingTimeInterval(-60 * 60)

    #expect(
      ArchivePolicy.shouldArchive(
        trigger: .daily, retention: 10, lastArchive: yesterday, now: now))
    #expect(
      !ArchivePolicy.shouldArchive(
        trigger: .daily, retention: 10, lastArchive: anHourAgo, now: now))
    #expect(
      ArchivePolicy.shouldArchive(trigger: .daily, retention: 10, lastArchive: nil, now: now),
      "never archived means due")
  }

  private func archive(_ offsetDays: Int) -> PadArchive {
    let taken = now.addingTimeInterval(Double(offsetDays) * 86_400)
    return PadArchive(
      id: ArchivePolicy.directoryName(for: taken), taken: taken, padCount: 3, byteCount: 1_000)
  }

  /// The oldest go, and the newest is always kept — the opposite would discard
  /// the only snapshot worth having.
  @Test("Pruning removes the oldest beyond the limit")
  func pruning() {
    // Oldest first, so the expectation reads in the same order as the result.
    let all = (1...5).map { archive(-(6 - $0)) }
    let oldestTwo = Array(all.prefix(2))
    let newest = try? #require(all.last)

    let doomed = ArchivePolicy.pruning(all, retention: 3)

    #expect(doomed.map(\.id) == oldestTwo.map(\.id))
    #expect(!doomed.map(\.id).contains(newest?.id ?? ""), "the newest must survive")
  }

  @Test("Nothing is pruned while under the limit")
  func nothingToPrune() {
    #expect(ArchivePolicy.pruning((1...3).map { archive(-$0) }, retention: 10).isEmpty)
    #expect(ArchivePolicy.pruning([], retention: 10).isEmpty)
  }

  @Test("Retention of zero prunes everything")
  func pruneAll() {
    #expect(ArchivePolicy.pruning((1...4).map { archive(-$0) }, retention: 0).count == 4)
  }

  @Test("A requested retention is clamped into range")
  func clamping() {
    #expect(ArchiveBounds.clamp(-5) == 0)
    #expect(ArchiveBounds.clamp(10) == 10)
    #expect(ArchiveBounds.clamp(9_999) == ArchiveBounds.maximumRetention)
  }

  /// Without this, a launch-and-quit cycle takes two identical snapshots and a
  /// day of restarts pushes the useful one off the end.
  @Test("An unchanged store is recognised as unchanged")
  func fingerprints() {
    let modified = Date(timeIntervalSince1970: 1_788_000_000)
    let first = ArchivePolicy.fingerprint(padCount: 3, latestModification: modified)
    let same = ArchivePolicy.fingerprint(padCount: 3, latestModification: modified)
    let edited = ArchivePolicy.fingerprint(
      padCount: 3, latestModification: modified.addingTimeInterval(60))
    let added = ArchivePolicy.fingerprint(padCount: 4, latestModification: modified)

    #expect(!ArchivePolicy.hasChanged(since: first, current: same))
    #expect(ArchivePolicy.hasChanged(since: first, current: edited))
    #expect(ArchivePolicy.hasChanged(since: first, current: added))
    #expect(ArchivePolicy.hasChanged(since: nil, current: first), "never archived is a change")
  }

  /// Colons are what ISO 8601 uses and what Finder renders as a slash.
  @Test("Directory names sort chronologically and contain no colons")
  func directoryNames() {
    let earlier = ArchivePolicy.directoryName(for: now)
    let later = ArchivePolicy.directoryName(for: now.addingTimeInterval(3_600))
    #expect(earlier < later)
    #expect(!earlier.contains(":"))
    #expect(ArchivePolicy.date(fromDirectoryName: earlier) != nil)
    #expect(ArchivePolicy.date(fromDirectoryName: "not-an-archive") == nil)
  }
}

@Suite("Archive store")
struct ArchiveStoreTests {
  private let now = Date(timeIntervalSince1970: 1_789_000_000)

  private func storeWithPads(_ count: Int, root: borrowing TemporaryRoot) async throws -> PadStore {
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    for index in 0..<count {
      let pad = try await store.createPad(name: "pad \(index)")
      await store.stage(PadContent.plainText("content \(index)"), for: pad.id, origin: .user)
    }
    try await store.flushAll()
    return store
  }

  @Test("An archive copies every pad and the index")
  func takesAnArchive() async throws {
    let root = TemporaryRoot()
    _ = try await storeWithPads(3, root: root)
    let archives = ArchiveStore(layout: root.layout)

    let archive = try #require(try archives.takeArchive(now: now))

    #expect(archive.padCount == 3)
    #expect(archive.byteCount > 0)
    let directory = root.layout.archiveDirectory(named: archive.id)
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("index.json").path))
    let padsInArchive = try FileManager.default.contentsOfDirectory(
      atPath: directory.appendingPathComponent("pads").path)
    #expect(padsInArchive.count == 3)
  }

  /// The point of the whole feature: the content has to come back.
  @Test("Archived content is intact and restorable by copying the directory back")
  func contentSurvives() async throws {
    let root = TemporaryRoot()
    let store = try await storeWithPads(2, root: root)
    let padID = try #require(await store.pads.first?.id)
    let archives = ArchiveStore(layout: root.layout)
    let archive = try #require(try archives.takeArchive(now: now))

    // Destroy the live pads entirely.
    try FileManager.default.removeItem(at: root.layout.padsDirectory)

    // Restore by moving the archived copy back into place.
    try FileManager.default.moveItem(
      at: root.layout.archiveDirectory(named: archive.id).appendingPathComponent("pads"),
      to: root.layout.padsDirectory)

    let recovered = PadStore(layout: root.layout, now: FixedClock().now)
    await recovered.load()
    #expect(await recovered.pads.count == 2)
    #expect(try await recovered.content(of: padID).plainText == "content 0")
  }

  @Test("An empty store has nothing worth archiving")
  func emptyStore() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    #expect(try ArchiveStore(layout: root.layout).takeArchive(now: now) == nil)
  }

  @Test("Archives are listed newest last and carry their timestamps")
  func listing() async throws {
    let root = TemporaryRoot()
    _ = try await storeWithPads(1, root: root)
    let archives = ArchiveStore(layout: root.layout)

    _ = try archives.takeArchive(now: now)
    _ = try archives.takeArchive(now: now.addingTimeInterval(3_600))
    _ = try archives.takeArchive(now: now.addingTimeInterval(7_200))

    let listed = archives.archives()
    #expect(listed.count == 3)
    #expect(listed == listed.sorted(), "oldest first")
    #expect(listed.last?.taken == now.addingTimeInterval(7_200))
  }

  @Test("Pruning removes the oldest and keeps the newest")
  func pruning() async throws {
    let root = TemporaryRoot()
    _ = try await storeWithPads(1, root: root)
    let archives = ArchiveStore(layout: root.layout)
    for hour in 0..<5 {
      _ = try archives.takeArchive(now: now.addingTimeInterval(Double(hour) * 3_600))
    }

    let removed = archives.prune(retention: 2)

    #expect(removed.count == 3)
    let remaining = archives.archives()
    #expect(remaining.count == 2)
    #expect(remaining.last?.taken == now.addingTimeInterval(4 * 3_600))
  }

  @Test("Removing everything leaves nothing behind")
  func removeAll() async throws {
    let root = TemporaryRoot()
    _ = try await storeWithPads(1, root: root)
    let archives = ArchiveStore(layout: root.layout)
    _ = try archives.takeArchive(now: now)

    archives.removeAll()

    #expect(archives.archives().isEmpty)
    #expect(archives.totalBytes() == 0)
  }

  /// `NFR-3.4`: an archive that is indexed when the original is not would be a
  /// privacy hole opened by the thing meant to prevent data loss.
  @Test("Archives live in a directory Spotlight will not index")
  func spotlightExclusion() {
    #expect(PadStorageLayout.archivesDirectoryName.hasSuffix(".noindex"))
  }

  @Test("The fingerprint changes when a pad is edited")
  func fingerprintTracksEdits() async throws {
    let root = TemporaryRoot()
    let store = try await storeWithPads(1, root: root)
    let archives = ArchiveStore(layout: root.layout)
    let before = archives.fingerprint()

    let padID = try #require(await store.pads.first?.id)
    try await Task.sleep(for: .milliseconds(1_100))
    await store.stage(PadContent.plainText("changed"), for: padID, origin: .user)
    try await store.flush(padID)

    #expect(ArchivePolicy.hasChanged(since: before, current: archives.fingerprint()))
  }

  @Test("An interrupted archive leaves no half-written directory")
  func interruptedArchive() async throws {
    let root = TemporaryRoot()
    _ = try await storeWithPads(2, root: root)
    let fileSystem = FaultInjectingFileSystem()
    fileSystem.arm(.write, on: "pads")
    let archives = ArchiveStore(layout: root.layout, fileSystem: fileSystem)

    #expect(throws: (any Error).self) {
      _ = try archives.takeArchive(now: now)
    }

    fileSystem.disarm()
    #expect(ArchiveStore(layout: root.layout).archives().isEmpty)
  }
}
