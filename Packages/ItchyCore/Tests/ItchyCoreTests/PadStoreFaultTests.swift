import Foundation
import Testing

@testable import ItchyCore

/// Sprint 1's exit gate requires every case in `PadStoreFault` to be exercised —
/// not eighty per cent of them, all of them, because a fault case with no test is
/// a fault case that has never executed.
///
/// Each case asserts two things: that the store remains usable afterwards
/// (`NFR-2.2`), and that no case yields an empty editable pad over unreadable
/// content, which specification §6.7 prohibits because it would destroy the
/// content on the next save.
@Suite("Store faults")
struct PadStoreFaultTests {
  /// A helper that builds a pad on disk and then damages it.
  private func storeWithPads(
    _ names: [String],
    root: borrowing TemporaryRoot
  ) async throws -> (PadStore, [PadID]) {
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    var ids: [PadID] = []
    for name in names {
      let pad = try await store.createPad(name: name)
      await store.stage(PadContent.plainText("content of \(name)"), for: pad.id, origin: .user)
      try await store.flush(pad.id)
      ids.append(pad.id)
    }
    try await store.flushAll()
    return (store, ids)
  }

  @Test("metadataUnreadable: truncated meta.json leaves other pads usable")
  func metadataUnreadable() async throws {
    let root = TemporaryRoot()
    let (_, ids) = try await storeWithPads(["good", "bad"], root: root)
    try Data("{ this is not json".utf8).write(to: root.layout.metadataFile(for: ids[1]))

    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()

    #expect(await store.pads.map(\.name) == ["good"])
    let fault = try #require(await store.fault(for: ids[1]))
    #expect(fault.prohibitsEditing)
    #expect(!(await store.isEditable(ids[1])))
    #expect(try await store.content(of: ids[0]).plainText == "content of good")
  }

  @Test("metadataUnreadable: an absent meta.json is a fault, not a silent skip")
  func metadataAbsent() async throws {
    let root = TemporaryRoot()
    let (_, ids) = try await storeWithPads(["gone"], root: root)
    try FileManager.default.removeItem(at: root.layout.metadataFile(for: ids[0]))

    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()

    let fault = try #require(await store.fault(for: ids[0]))
    #expect(fault == .metadataUnreadable(ids[0], underlying: "meta.json is absent"))
    #expect(fault.prohibitsEditing)
  }

  /// `FR-5.8`: a file from a newer build is reported unreadable rather than
  /// guessed at.
  @Test("metadataSchemaTooNew: a future schema version is refused")
  func schemaTooNew() async throws {
    let root = TemporaryRoot()
    let (_, ids) = try await storeWithPads(["future"], root: root)
    let file = root.layout.metadataFile(for: ids[0])
    var object = try JSONCoding.decoder()
      .decode([String: JSONValue].self, from: try Data(contentsOf: file))
    object["schemaVersion"] = .number(99)
    try JSONCoding.encoder().encode(object).write(to: file)

    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()

    #expect(
      await store.fault(for: ids[0])
        == .metadataSchemaTooNew(ids[0], found: 99, supported: ItchyCore.schemaVersion))
    #expect(!(await store.isEditable(ids[0])))
  }

  @Test("contentMissing: an absent content directory never yields an empty editor")
  func contentMissing() async throws {
    let root = TemporaryRoot()
    let (_, ids) = try await storeWithPads(["hollow"], root: root)
    try FileManager.default.removeItem(at: root.layout.contentDirectory(for: ids[0]))

    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()

    // Detected at load by a stat, not by reading content (FR-1.6), so that the
    // menubar can list the pad as faulted rather than only discovering it when
    // the user opens it (specification §6.7).
    #expect(await store.fault(for: ids[0]) == .contentMissing(ids[0]))
    #expect(!(await store.isEditable(ids[0])))

    await #expect(throws: PadStoreFault.contentMissing(ids[0])) {
      _ = try await store.content(of: ids[0])
    }
    #expect(await store.pads.count == 1, "the pad is still listed, just not editable")
  }

  @Test("contentUnreadable: an unreadable bundle is a fault, not empty content")
  func contentUnreadable() async throws {
    let root = TemporaryRoot()
    let (_, ids) = try await storeWithPads(["unreadable"], root: root)

    let fileSystem = FaultInjectingFileSystem()
    fileSystem.arm(.read, on: "TXT.rtf")
    let store = PadStore(layout: root.layout, fileSystem: fileSystem, now: FixedClock().now)
    await store.load()

    await #expect(throws: (any Error).self) {
      _ = try await store.content(of: ids[0])
    }
    let fault = try #require(await store.fault(for: ids[0]))
    #expect(fault.prohibitsEditing)
    #expect(!(await store.isEditable(ids[0])))
  }

  /// The shadow file is derived and never authoritative (`FR-5.4`), so a
  /// disagreement is reportable but must not block editing — the bundle is right.
  @Test("shadowDesynchronised does not prohibit editing")
  func shadowDesynchronised() {
    let id = PadID()
    let fault = PadStoreFault.shadowDesynchronised(id)
    #expect(!fault.prohibitsEditing)
    #expect(fault.padID == id)
    #expect(fault.reason.contains("shadow text"))
  }

  /// `NFR-2.2`: an unreadable index is rebuilt by enumeration rather than
  /// preventing launch.
  @Test("indexUnreadable: the index is rebuilt from the pads directory")
  func indexUnreadable() async throws {
    let root = TemporaryRoot()
    let (_, ids) = try await storeWithPads(["a", "b", "c"], root: root)
    try Data("not json at all".utf8).write(to: root.layout.indexFile)

    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()

    #expect(await store.pads.count == 3)
    #expect(Set(await store.pads.map(\.id)) == Set(ids))
  }

  @Test("An index naming a pad that does not exist drops it")
  func indexNamesAGhost() async throws {
    let root = TemporaryRoot()
    let (_, ids) = try await storeWithPads(["real"], root: root)
    let ghost = PadID()
    let index = PadIndex(order: [ghost, ids[0]], lastOpened: ghost)
    try JSONCoding.encoder().encode(index).write(to: root.layout.indexFile)

    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()

    #expect(await store.pads.map(\.id) == [ids[0]])
    #expect(await store.lastOpenedPad == nil)
  }

  @Test("A pad present on disk but absent from the index is appended")
  func indexOmitsAPad() async throws {
    let root = TemporaryRoot()
    let (_, ids) = try await storeWithPads(["listed", "unlisted"], root: root)
    try JSONCoding.encoder()
      .encode(PadIndex(order: [ids[0]]))
      .write(to: root.layout.indexFile)

    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()

    #expect(await store.pads.count == 2)
    #expect(await store.pads.first?.id == ids[0])
  }

  @Test("writeFailed: a failing write surfaces and leaves prior content intact")
  func writeFailed() async throws {
    let root = TemporaryRoot()
    let clock = FixedClock()
    let plain = PadStore(layout: root.layout, now: clock.now)
    await plain.load()
    let pad = try await plain.createPad(name: "fragile")
    await plain.stage(PadContent.plainText("original"), for: pad.id, origin: .user)
    try await plain.flush(pad.id)

    let fileSystem = FaultInjectingFileSystem()
    let store = PadStore(layout: root.layout, fileSystem: fileSystem, now: clock.now)
    await store.load()
    fileSystem.arm(.replace, on: "meta.json")
    await store.stage(PadContent.plainText("doomed"), for: pad.id, origin: .user)

    await #expect(throws: (any Error).self) {
      try await store.flush(pad.id)
    }

    fileSystem.disarm()
    let after = PadStore(layout: root.layout, now: clock.now)
    await after.load()
    #expect(await after.pads.first?.name == "fragile")
  }

  @Test("diskSpaceExhausted is distinguished from an ordinary write failure")
  func diskFull() async throws {
    let root = TemporaryRoot()
    let fileSystem = FaultInjectingFileSystem()
    let store = PadStore(layout: root.layout, fileSystem: fileSystem, now: FixedClock().now)
    await store.load()
    let pad = try await store.createPad(name: "roomy")

    fileSystem.arm(.diskFull, on: ".tmp")
    await store.stage(PadContent.plainText("too big"), for: pad.id, origin: .user)

    await #expect(throws: PadStoreFault.diskSpaceExhausted) {
      try await store.flush(pad.id)
    }
  }

  @Test("padLimitReached carries the limit that was reached")
  func padLimitReached() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load(padLimit: 1)
    _ = try await store.createPad(name: "only")

    await #expect(throws: PadStoreFault.padLimitReached(limit: 1)) {
      _ = try await store.createPad(name: "extra")
    }
    #expect(await store.pads.count == 1)
  }

  @Test("unknownPad is reported rather than ignored")
  func unknownPad() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    let ghost = PadID()
    await #expect(throws: PadStoreFault.unknownPad(ghost)) {
      _ = try await store.content(of: ghost)
    }
    #expect(PadStoreFault.unknownPad(ghost).padID == ghost)
    #expect(!PadStoreFault.unknownPad(ghost).prohibitsEditing)
  }

  /// The rule from specification §6.7, asserted over every case at once rather
  /// than relying on each test above to remember it.
  @Test(
    "No fault that prohibits editing can be mistaken for readable content",
    arguments: [
      PadStoreFault.metadataUnreadable(PadID(), underlying: "x"),
      .metadataSchemaTooNew(PadID(), found: 9, supported: 1),
      .contentUnreadable(PadID(), underlying: "x"),
      .contentMissing(PadID()),
    ])
  func prohibitingFaults(fault: PadStoreFault) {
    #expect(fault.prohibitsEditing)
    #expect(!fault.reason.isEmpty)
  }

  @Test(
    "Faults that do not concern readable content permit editing",
    arguments: [
      PadStoreFault.shadowDesynchronised(PadID()),
      .indexUnreadable(underlying: "x"),
      .writeFailed(PadID(), underlying: "x"),
      .padLimitReached(limit: 9),
      .diskSpaceExhausted,
      .unknownPad(PadID()),
    ])
  func permittingFaults(fault: PadStoreFault) {
    #expect(!fault.prohibitsEditing)
    #expect(!fault.reason.isEmpty)
  }

  @Test("Every fault case is covered by this suite")
  func taxonomyIsFullyCovered() {
    // Enumerated by hand because the type carries associated values and cannot
    // be CaseIterable. If a case is added to PadStoreFault and not added here,
    // this list and the suite above are the two places that must change.
    let covered: [PadStoreFault] = [
      .metadataUnreadable(PadID(), underlying: ""),
      .metadataSchemaTooNew(PadID(), found: 0, supported: 0),
      .contentUnreadable(PadID(), underlying: ""),
      .contentMissing(PadID()),
      .shadowDesynchronised(PadID()),
      .indexUnreadable(underlying: ""),
      .writeFailed(nil, underlying: ""),
      .padLimitReached(limit: 0),
      .diskSpaceExhausted,
      .unknownPad(PadID()),
    ]
    #expect(covered.count == 10, "PadStoreFault has a case with no test")
    #expect(PadStoreFault.writeFailed(nil, underlying: "x").padID == nil)
    #expect(PadStoreFault.diskSpaceExhausted.padID == nil)
  }
}
