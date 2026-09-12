import Foundation
import Testing

@testable import ItchyCore

/// Collects change events without spinning.
///
/// Waiting is by predicate rather than by count, because `AsyncStream` buffers:
/// events yielded before the consumer starts are delivered when it does, so a
/// count-based wait returns on whichever event happens to arrive first rather
/// than on the one the test is about.
actor ChangeLog {
  private var events: [PadChange] = []
  private var predicate: (@Sendable ([PadChange]) -> Bool)?
  private var waiter: CheckedContinuation<Void, Never>?

  func record(_ change: PadChange) {
    events.append(change)
    guard let predicate, predicate(events) else { return }
    let continuation = waiter
    waiter = nil
    self.predicate = nil
    continuation?.resume()
  }

  var all: [PadChange] { events }

  func waitFor(_ count: Int) async {
    await waitUntil { $0.count >= count }
  }

  /// Waits until `count` events satisfying `match` have been seen.
  func waitFor(count: Int = 1, matching match: @escaping @Sendable (PadChange) -> Bool) async {
    await waitUntil { $0.filter(match).count >= count }
  }

  private func waitUntil(_ condition: @escaping @Sendable ([PadChange]) -> Bool) async {
    guard !condition(events) else { return }
    predicate = condition
    await withCheckedContinuation { waiter = $0 }
  }
}

/// Whether a change is a size-threshold crossing.
@Sendable func isSizeCrossing(_ change: PadChange) -> Bool {
  if case .sizeThresholdCrossed = change { return true }
  return false
}

@Suite("Store observation")
struct PadStoreObservationTests {
  private func observe(_ store: PadStore) -> ChangeLog {
    let log = ChangeLog()
    Task {
      for await change in await store.changes {
        await log.record(change)
      }
    }
    return log
  }

  @Test("Creating, renaming, reordering and deleting each announce themselves")
  func lifecycleEvents() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    let log = observe(store)

    let first = try await store.createPad(name: "a")
    let second = try await store.createPad(name: "b")
    try await store.rename(first.id, to: "renamed")
    try await store.reorder(to: [second.id, first.id])
    try await store.deletePad(second.id)

    await log.waitFor(5)
    let events = await log.all
    #expect(events.contains(.padAdded(first.id)))
    #expect(events.contains(.metadataChanged(first.id)))
    #expect(events.contains(.padsReordered([second.id, first.id])))
    #expect(events.contains(.padRemoved(second.id)))
  }

  /// `FR-8.9`: a write from any origin other than the user is announced and
  /// marked, so the interface can tell the user something happened to the pad.
  @Test("An external write is announced and marked, a user write is neither")
  func externalWriteMarking() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    let pad = try await store.createPad(name: "shared")
    let log = observe(store)

    await store.stage(PadContent.plainText("typed"), for: pad.id, origin: .user)
    #expect(await store.pads.first?.externalWriteMarker == nil)

    await store.stage(PadContent.plainText("from an agent"), for: pad.id, origin: .mcp(client: "claude"))
    await log.waitFor(1)

    let marker = try #require(await store.pads.first?.externalWriteMarker)
    #expect(marker.origin == .mcp(client: "claude"))
    #expect(marker.characterDelta == "from an agent".count)
    #expect(await log.all.contains(.contentChangedExternally(pad.id, origin: .mcp(client: "claude"))))
  }

  @Test("A transform write is external too")
  func transformIsExternal() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    let pad = try await store.createPad(name: "transformed")

    await store.stage(PadContent.plainText("{}"), for: pad.id, origin: .transform("json.pretty"))

    #expect(await store.pads.first?.externalWriteMarker?.origin == .transform("json.pretty"))
    #expect(WriteOrigin.transform("x").isExternal)
    #expect(WriteOrigin.mcp(client: nil).isExternal)
    #expect(!WriteOrigin.user.isExternal)
  }

  @Test("The external-write marker can be cleared once the user has seen it")
  func clearMarker() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    let pad = try await store.createPad(name: "x")
    await store.stage(PadContent.plainText("agent"), for: pad.id, origin: .mcp(client: nil))

    await store.clearExternalWriteMarker(of: pad.id)

    #expect(await store.pads.first?.externalWriteMarker == nil)
  }

  /// `FR-5.9`: pad size is surfaced once it passes the threshold, so that a pad
  /// accumulating screenshots cannot grow unnoticed.
  @Test("Crossing the size threshold is announced once, not on every save")
  func sizeThreshold() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    let pad = try await store.createPad(name: "heavy")
    let log = observe(store)

    let big = Data(repeating: 0x41, count: PadStore.sizeMarkerThreshold + 1)
    await store.stage(PadContent(bundle: ["TXT.rtf": big], plainText: "x"), for: pad.id, origin: .user)
    await log.waitFor(matching: isSizeCrossing)
    await store.stage(PadContent(bundle: ["TXT.rtf": big], plainText: "y"), for: pad.id, origin: .user)
    await log.waitFor(2)

    #expect(await log.all.filter(isSizeCrossing).count == 1)
  }

  @Test("Dropping back under the threshold re-arms the marker")
  func thresholdRearms() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    let pad = try await store.createPad(name: "shrinking")
    let log = observe(store)
    let big = Data(repeating: 0x41, count: PadStore.sizeMarkerThreshold + 1)

    await store.stage(PadContent(bundle: ["TXT.rtf": big], plainText: "x"), for: pad.id, origin: .user)
    await log.waitFor(matching: isSizeCrossing)
    await store.stage(PadContent.plainText("small"), for: pad.id, origin: .user)
    await store.stage(PadContent(bundle: ["TXT.rtf": big], plainText: "x"), for: pad.id, origin: .user)
    await log.waitFor(count: 2, matching: isSizeCrossing)

    #expect(await log.all.filter(isSizeCrossing).count == 2)
  }

  @Test("A store fault is announced to observers")
  func faultsAreAnnounced() async throws {
    let root = TemporaryRoot()
    let clock = FixedClock()
    let seeded = PadStore(layout: root.layout, now: clock.now)
    await seeded.load()
    let pad = try await seeded.createPad(name: "doomed")
    try await seeded.flushAll()
    try Data("broken".utf8).write(to: root.layout.metadataFile(for: pad.id))

    let store = PadStore(layout: root.layout, now: clock.now)
    let log = observe(store)
    await store.load()
    await log.waitFor(matching: { if case .storeFault = $0 { return true } else { return false } })

    #expect(
      await log.all.contains {
        if case .storeFault = $0 { return true } else { return false }
      })
  }
}

@Suite("Store provenance and state")
struct PadStoreProvenanceTests {
  /// `FR-7.2`: provenance lives in metadata, not in text attributes, so that
  /// flattening a pad leaves it intact.
  @Test("Provenance is appended, persisted and clearable")
  func provenance() async throws {
    let root = TemporaryRoot()
    let clock = FixedClock()
    let store = PadStore(layout: root.layout, now: clock.now)
    await store.load()
    let pad = try await store.createPad(name: "pasted")

    await store.appendProvenance(
      ProvenanceEntry(
        arrived: clock.instant,
        sourceBundleID: "com.apple.Safari",
        sourceAppName: "Safari",
        sourceURL: URL(string: "https://example.invalid/x"),
        approximateRange: 0..<12,
        byteCount: 12,
        kind: .styledText),
      to: pad.id)
    try await store.flush(pad.id)

    let reloaded = PadStore(layout: root.layout, now: clock.now)
    await reloaded.load()
    #expect(await reloaded.pads.first?.provenance.count == 1)
    #expect(await reloaded.pads.first?.provenance.first?.sourceAppName == "Safari")

    await reloaded.clearProvenance(of: pad.id)
    try await reloaded.flush(pad.id)
    #expect(await reloaded.pads.first?.provenance.isEmpty == true)
  }

  @Test("Clearing provenance does not alter content (FR-7.5)")
  func clearingKeepsContent() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    let pad = try await store.createPad(name: "x")
    await store.stage(PadContent.plainText("untouched"), for: pad.id, origin: .user)
    await store.appendProvenance(
      ProvenanceEntry(arrived: Date(), byteCount: 1, kind: .text), to: pad.id)

    await store.clearProvenance(of: pad.id)

    #expect(try await store.content(of: pad.id).plainText == "untouched")
  }

  @Test("Provenance on an unknown pad is ignored rather than crashing")
  func provenanceOnGhost() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    await store.appendProvenance(
      ProvenanceEntry(arrived: Date(), byteCount: 1, kind: .text), to: PadID())
    await store.clearProvenance(of: PadID())
    await store.setFrame(PadID(), PadFrame(x: 0, y: 0, width: 1, height: 1))
    await store.markOpened(PadID())
    await store.stage(PadContent.plainText("x"), for: PadID(), origin: .user)
    #expect(await store.pads.isEmpty)
  }

  @Test("Opening a pad records it as the hotkey target (FR-1.4)")
  func lastOpened() async throws {
    let root = TemporaryRoot()
    let clock = FixedClock()
    let store = PadStore(layout: root.layout, now: clock.now)
    await store.load()
    let first = try await store.createPad(name: "a")
    let second = try await store.createPad(name: "b")

    await store.markOpened(first.id)
    await store.markOpened(second.id)
    try await store.flushAll()

    #expect(await store.lastOpenedPad == second.id)
    let reloaded = PadStore(layout: root.layout, now: clock.now)
    await reloaded.load()
    #expect(await reloaded.lastOpenedPad == second.id)
  }

  @Test("Exposure and routing policy are per-pad and persist")
  func exposureAndRouting() async throws {
    let root = TemporaryRoot()
    let clock = FixedClock()
    let store = PadStore(layout: root.layout, now: clock.now)
    await store.load()
    let pad = try await store.createPad(name: "agent-visible")

    #expect(await store.pads.first?.isExposedToMCP == false, "not exposed by default (FR-8.7)")
    #expect(await store.pads.first?.routingPolicy == .localOnly, "local by default (FR-9.1)")

    try await store.setExposedToMCP(pad.id, true)
    try await store.setRoutingPolicy(pad.id, .remotePermitted)

    let reloaded = PadStore(layout: root.layout, now: clock.now)
    await reloaded.load()
    #expect(await reloaded.pads.first?.isExposedToMCP == true)
    #expect(await reloaded.pads.first?.routingPolicy == .remotePermitted)
  }

  @Test("Staging marks the pad dirty until it is flushed")
  func dirtyTracking() async throws {
    let root = TemporaryRoot()
    let sleeper = ControlledSleeper()
    let store = PadStore(
      layout: root.layout, scheduler: SaveScheduler(sleeper: sleeper), now: FixedClock().now)
    await store.load()
    let pad = try await store.createPad(name: "x")
    #expect(!(await store.isDirty(pad.id)))

    await store.stage(PadContent.plainText("typed"), for: pad.id, origin: .user)
    #expect(await store.isDirty(pad.id))
    #expect(await store.hasPendingWrite(pad.id))

    try await store.flush(pad.id)
    #expect(!(await store.isDirty(pad.id)))
    #expect(!(await store.hasPendingWrite(pad.id)))
  }
}

@Suite("Pad content")
struct PadContentTests {
  @Test("An empty pad carries an RTF document and no attachments")
  func empty() {
    let content = PadContent.empty()
    #expect(content.document != nil)
    #expect(content.attachmentNames.isEmpty)
    #expect(content.plainText.isEmpty)
  }

  @Test("Byte count totals the whole bundle, which is what the size marker uses")
  func byteCount() {
    let content = PadContent(
      bundle: ["TXT.rtf": Data(repeating: 1, count: 10), "a.png": Data(repeating: 2, count: 90)],
      plainText: "")
    #expect(content.byteCount == 100)
    #expect(content.attachmentNames == ["a.png"])
  }

  @Test("RTF special characters are escaped rather than corrupting the document")
  func escaping() throws {
    let content = PadContent.plainText(#"a \ b { c } d"#)
    let document = try #require(content.document)
    let rtf = try #require(String(bytes: document, encoding: .utf8))
    #expect(rtf.contains(#"\\"#))
    #expect(rtf.contains(#"\{"#))
    #expect(rtf.contains(#"\}"#))
    #expect(content.plainText == #"a \ b { c } d"#)
  }
}
