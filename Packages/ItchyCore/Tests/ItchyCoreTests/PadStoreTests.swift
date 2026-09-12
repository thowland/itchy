import Foundation
import Testing

@testable import ItchyCore

@Suite("Pad store lifecycle")
struct PadStoreLifecycleTests {
  @Test("Creating a pad requires no input and is immediately readable (FR-2.3)")
  func creation() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()

    let pad = try await store.createPad(name: nil)

    #expect(pad.name == "Pad 1")
    #expect(pad.mode == .styled)
    #expect(await store.pads.map(\.id) == [pad.id])
    #expect(try await store.content(of: pad.id).plainText.isEmpty)
  }

  @Test("Default names do not collide")
  func defaultNames() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    _ = try await store.createPad(name: nil)
    _ = try await store.createPad(name: nil)
    #expect(await store.pads.map(\.name) == ["Pad 1", "Pad 2"])
  }

  @Test("Content survives a store being rebuilt from disk (FR-5.1)")
  func retentionAcrossLoad() async throws {
    let root = TemporaryRoot()
    let clock = FixedClock()
    let first = PadStore(layout: root.layout, now: clock.now)
    await first.load()
    let pad = try await first.createPad(name: "keeper")
    await first.stage(PadContent.plainText("held indefinitely"), for: pad.id, origin: .user)
    try await first.flushAll()

    let second = PadStore(layout: root.layout, now: clock.now)
    await second.load()

    #expect(await second.pads.map(\.name) == ["keeper"])
    #expect(try await second.content(of: pad.id).plainText == "held indefinitely")
  }

  @Test("Rename, mode and pin persist (FR-2.4, FR-2.7, FR-2.8)")
  func metadataPersists() async throws {
    let root = TemporaryRoot()
    let clock = FixedClock()
    let store = PadStore(layout: root.layout, now: clock.now)
    await store.load()
    let pad = try await store.createPad(name: "before")

    try await store.rename(pad.id, to: "after")
    try await store.setMode(pad.id, to: .plain)
    try await store.setPinned(pad.id, true)

    let reloaded = PadStore(layout: root.layout, now: clock.now)
    await reloaded.load()
    let meta = try #require(await reloaded.pads.first)
    #expect(meta.name == "after")
    #expect(meta.mode == .plain)
    #expect(meta.isPinned)
  }

  @Test("Slot order persists (FR-2.5)")
  func orderPersists() async throws {
    let root = TemporaryRoot()
    let clock = FixedClock()
    let store = PadStore(layout: root.layout, now: clock.now)
    await store.load()
    let first = try await store.createPad(name: "a")
    let second = try await store.createPad(name: "b")
    let third = try await store.createPad(name: "c")

    try await store.reorder(to: [third.id, first.id, second.id])
    try await store.flushAll()

    let reloaded = PadStore(layout: root.layout, now: clock.now)
    await reloaded.load()
    #expect(await reloaded.pads.map(\.name) == ["c", "a", "b"])
  }

  @Test("A reorder that omits a pad appends it rather than losing it")
  func reorderCannotLoseAPad() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    let first = try await store.createPad(name: "a")
    let second = try await store.createPad(name: "b")

    try await store.reorder(to: [second.id])

    #expect(await store.pads.count == 2)
    #expect(await store.pads.map(\.id) == [second.id, first.id])
  }

  @Test("Deleting a pad removes its directory")
  func deletion() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    let pad = try await store.createPad(name: "doomed")
    let directory = root.layout.directory(for: pad.id)
    #expect(FileManager.default.fileExists(atPath: directory.path))

    try await store.deletePad(pad.id)

    #expect(await store.pads.isEmpty)
    #expect(!FileManager.default.fileExists(atPath: directory.path))
  }

  @Test("Operations on an unknown pad throw rather than doing nothing quietly")
  func unknownPad() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    let ghost = PadID()

    await #expect(throws: PadStoreFault.unknownPad(ghost)) {
      try await store.rename(ghost, to: "x")
    }
    await #expect(throws: PadStoreFault.unknownPad(ghost)) {
      _ = try await store.content(of: ghost)
    }
    await #expect(throws: PadStoreFault.unknownPad(ghost)) {
      try await store.deletePad(ghost)
    }
  }

  @Test("The frame is stored against the pad, not in an autosave slot (FR-3.4)")
  func framePersists() async throws {
    let root = TemporaryRoot()
    let clock = FixedClock()
    let store = PadStore(layout: root.layout, now: clock.now)
    await store.load()
    let pad = try await store.createPad(name: "framed")
    let frame = PadFrame(x: 100, y: 200, width: 420, height: 560, displayID: 7)

    await store.setFrame(pad.id, frame)
    try await store.flushAll()

    let reloaded = PadStore(layout: root.layout, now: clock.now)
    await reloaded.load()
    #expect(await reloaded.pads.first?.frame == frame)
  }

  @Test("A frame change does not mark content dirty (specification §8.4)")
  func frameIsNotAContentWrite() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    let pad = try await store.createPad(name: "x")
    try await store.flush(pad.id)

    await store.setFrame(pad.id, PadFrame(x: 1, y: 2, width: 3, height: 4))

    // Dirty for the metadata write, but the content cache is untouched.
    #expect(try await store.content(of: pad.id).plainText.isEmpty)
  }
}

@Suite("Pad store persistence")
struct PadStorePersistenceTests {
  /// `FR-5.2`: the layout must be navigable with `ls` and `cat`.
  @Test("The on-disk layout is the documented one")
  func layout() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    let pad = try await store.createPad(name: "shapes")
    await store.stage(PadContent.plainText("hello"), for: pad.id, origin: .user)
    try await store.flushAll()

    let directory = root.layout.directory(for: pad.id)
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("meta.json").path))
    #expect(FileManager.default.fileExists(atPath: directory.appendingPathComponent("content.txt").path))
    var isDir = ObjCBool(false)
    _ = FileManager.default.fileExists(
      atPath: directory.appendingPathComponent("content.rtfd").path, isDirectory: &isDir)
    #expect(isDir.boolValue, "content.rtfd must be a directory so TextEdit can open it")
    #expect(FileManager.default.fileExists(atPath: root.layout.indexFile.path))
  }

  /// `FR-5.4`: written on every save, for every pad, regardless of mode and
  /// regardless of exposure. Never read back as authoritative.
  @Test("The shadow file matches the plain-text extraction on every save")
  func shadowFileIsWrittenAlways() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()

    for mode in PadMode.allCases {
      let pad = try await store.createPad(name: "pad-\(mode.rawValue)")
      try await store.setMode(pad.id, to: mode)
      await store.stage(PadContent.plainText("text for \(mode.rawValue)"), for: pad.id, origin: .user)
      try await store.flush(pad.id)

      let shadow = try Data(contentsOf: root.layout.shadowFile(for: pad.id))
      #expect(shadow == Data("text for \(mode.rawValue)".utf8))
    }
  }

  @Test("Deleting the shadow file and editing regenerates it")
  func shadowFileRegenerates() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    let pad = try await store.createPad(name: "x")
    await store.stage(PadContent.plainText("one"), for: pad.id, origin: .user)
    try await store.flush(pad.id)

    try FileManager.default.removeItem(at: root.layout.shadowFile(for: pad.id))
    await store.stage(PadContent.plainText("two"), for: pad.id, origin: .user)
    try await store.flush(pad.id)

    let shadow = try Data(contentsOf: root.layout.shadowFile(for: pad.id))
    #expect(shadow == Data("two".utf8))
  }

  /// `NFR-3.4`, D-16. The suffix is the whole mechanism: spike S-3 showed that
  /// `.metadata_never_index` has no effect on a directory, while a `.noindex`
  /// suffix does. A rename that drops the suffix silently restores indexing of
  /// every pad, so it is asserted rather than assumed.
  @Test("Pads live in a directory Spotlight will not index")
  func padsDirectoryIsExcludedFromSpotlight() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()

    #expect(root.layout.padsDirectory.lastPathComponent.hasSuffix(".noindex"))
    #expect(FileManager.default.fileExists(atPath: root.layout.padsDirectory.path))
  }

  /// An install written before D-16 must not keep its pads in the indexed
  /// location, or `NFR-3.4` holds only for pads created after the upgrade.
  @Test("An install predating the change is moved into the excluded directory")
  func legacyPadsAreMigrated() async throws {
    let root = TemporaryRoot()
    let clock = FixedClock()

    // Build an install the old way: pads under "pads".
    let legacy = root.layout.legacyPadsDirectory
    try FileManager.default.createDirectory(at: legacy, withIntermediateDirectories: true)
    let seeded = PadStore(
      layout: PadStorageLayout(root: root.url), now: clock.now)
    await seeded.load()
    let pad = try await seeded.createPad(name: "from before")
    try await seeded.flushAll()
    try? FileManager.default.removeItem(at: legacy)
    try FileManager.default.moveItem(at: root.layout.padsDirectory, to: legacy)

    let migrated = PadStore(layout: root.layout, now: clock.now)
    await migrated.load()

    #expect(await migrated.pads.map(\.name) == ["from before"])
    #expect(!FileManager.default.fileExists(atPath: legacy.path), "the old directory is gone")
    #expect(
      FileManager.default.fileExists(
        atPath: root.layout.directory(for: pad.id).path))
  }

  /// `FR-5.7`: an unknown field added by hand survives the next save.
  @Test("A hand-added metadata field survives a store round trip")
  func unknownFieldSurvivesTheStore() async throws {
    let root = TemporaryRoot()
    let clock = FixedClock()
    let store = PadStore(layout: root.layout, now: clock.now)
    await store.load()
    let pad = try await store.createPad(name: "annotated")
    try await store.flushAll()

    let file = root.layout.metadataFile(for: pad.id)
    var object = try JSONCoding.decoder()
      .decode([String: JSONValue].self, from: try Data(contentsOf: file))
    object["aFieldFromTheFuture"] = .string("keep me")
    try JSONCoding.encoder().encode(object).write(to: file)

    let reloaded = PadStore(layout: root.layout, now: clock.now)
    await reloaded.load()
    try await reloaded.rename(pad.id, to: "renamed")

    let after = try JSONCoding.decoder()
      .decode([String: JSONValue].self, from: try Data(contentsOf: file))
    #expect(after["aFieldFromTheFuture"] == .string("keep me"))
    #expect(after["name"] == .string("renamed"))
  }

  /// `NFR-2.1`: killing the process after a flush loses nothing.
  @Test("A forced flush makes content durable immediately")
  func flushIsDurable() async throws {
    let root = TemporaryRoot()
    let sleeper = ControlledSleeper()
    let store = PadStore(
      layout: root.layout,
      scheduler: SaveScheduler(sleeper: sleeper),
      now: FixedClock().now)
    await store.load()
    let pad = try await store.createPad(name: "durable")

    await store.stage(PadContent.plainText("typed then killed"), for: pad.id, origin: .user)
    try await store.flush(pad.id)

    // Nothing released the debounce, so only the forced flush can have written.
    let shadow = try Data(contentsOf: root.layout.shadowFile(for: pad.id))
    #expect(shadow == Data("typed then killed".utf8))
  }

  @Test("Content is not read at load time (FR-1.6)")
  func loadDoesNotReadContent() async throws {
    let root = TemporaryRoot()
    let clock = FixedClock()
    let store = PadStore(layout: root.layout, now: clock.now)
    await store.load()
    let pad = try await store.createPad(name: "lazy")
    await store.stage(PadContent.plainText("bytes"), for: pad.id, origin: .user)
    try await store.flushAll()

    let fileSystem = FaultInjectingFileSystem()
    let reloaded = PadStore(layout: root.layout, fileSystem: fileSystem, now: clock.now)
    await reloaded.load()

    // Metadata was read; no content directory was touched.
    #expect(await reloaded.pads.count == 1)
    #expect(!fileSystem.writes.contains("content.txt"))
    #expect(try await reloaded.content(of: pad.id).plainText == "bytes")
  }
}
