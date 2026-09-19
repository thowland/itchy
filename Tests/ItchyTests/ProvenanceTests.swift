import AppKit
import ItchyCore
import Testing

@testable import Itchy

/// Sprint 7: the list a pad keeps of what arrived in it, and from where.
@Suite("Provenance")
struct ProvenanceTests {
  private let now = Date(timeIntervalSince1970: 1_800_000_000)

  private func entry(
    app: String? = "Safari",
    url: URL? = URL(string: "https://example.com/a/page?utm=1"),
    kind: ProvenanceEntry.Kind = .styledText,
    bytes: Int = 2_048,
    ago: TimeInterval = 0
  ) -> ProvenanceEntry {
    ProvenanceEntry(
      arrived: now.addingTimeInterval(-ago),
      sourceBundleID: "com.apple.Safari",
      sourceAppName: app,
      sourceURL: url,
      approximateRange: 0..<10,
      byteCount: bytes,
      kind: kind)
  }

  private func pad(_ entries: [ProvenanceEntry]) -> PadMetadata {
    PadMetadata(name: "scratch", created: now, modified: now, provenance: entries)
  }

  // MARK: - FR-7.2, the reason the requirement exists

  /// The one the implementation plan names: "the test that matters is that
  /// flattening a pad leaves its provenance list intact, since that is the
  /// entire reason the data does not live in text attributes."
  @Test("Flattening a pad leaves its provenance intact (FR-7.2)")
  func survivesFlattening() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-prov-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PadStore(layout: PadStorageLayout(root: root))
    await store.load()
    let created = try await store.createPad(name: "scratch")

    let styled = NSMutableAttributedString(
      string: "pasted", attributes: [.font: NSFont.boldSystemFont(ofSize: 18)])
    await store.stage(try ContentCodec.encode(styled), for: created.id, origin: .user)
    await store.appendProvenance(entry(), to: created.id)

    // Flatten exactly as the interface does: the styling goes, the text stays.
    let flattened = ContentCodec.flatten(styled)
    await store.stage(try ContentCodec.encode(flattened), for: created.id, origin: .user)
    try await store.flush(created.id)

    let after = await store.pads.first { $0.id == created.id }
    #expect(after?.provenance.count == 1)
    #expect(after?.provenance.first?.sourceAppName == "Safari")
    // And the flatten really did happen, or the test proves nothing.
    let content = try await store.content(of: created.id)
    let decoded = try ContentCodec.decode(content)
    #expect(decoded.string == "pasted")
    #expect(
      (decoded.attribute(.font, at: 0, effectiveRange: nil) as? NSFont)?.pointSize
        != 18)
  }

  /// `FR-7.5`: clearing empties the list and leaves content unchanged.
  @Test("Clearing provenance leaves the pad's content alone")
  func clearingKeepsContent() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-prov-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PadStore(layout: PadStorageLayout(root: root))
    await store.load()
    let created = try await store.createPad(name: "scratch")
    await store.stage(PadContent.plainText("kept"), for: created.id, origin: .user)
    await store.appendProvenance(entry(), to: created.id)

    await store.clearProvenance(of: created.id)

    #expect(await store.pads.first { $0.id == created.id }?.provenance.isEmpty == true)
    #expect(try await store.content(of: created.id).plainText == "kept")
  }

  /// `FR-7.3` asks for "a short list" and "the last several arrivals". Several
  /// is not all: meta.json is rewritten in full on every save, so an unbounded
  /// list is a file that grows and is written forever.
  @Test("The list is bounded, keeping the newest")
  func boundedToTheNewest() async throws {
    let many = (0..<(ProvenanceBounds.limit + 10)).map { entry(app: "App\($0)") }
    let trimmed = ProvenanceBounds.trimmed(many)
    #expect(trimmed.count == ProvenanceBounds.limit)
    #expect(trimmed.first?.sourceAppName == "App10")
    #expect(trimmed.last?.sourceAppName == "App\(ProvenanceBounds.limit + 9)")
    // Under the limit nothing is touched.
    #expect(ProvenanceBounds.trimmed([entry()]).count == 1)
  }

  @Test("The store applies the bound as entries arrive")
  func storeBounds() async throws {
    let root = URL(fileURLWithPath: NSTemporaryDirectory())
      .appendingPathComponent("itchy-prov-\(UUID().uuidString)")
    defer { try? FileManager.default.removeItem(at: root) }
    let store = PadStore(layout: PadStorageLayout(root: root))
    await store.load()
    let created = try await store.createPad(name: "scratch")

    for index in 0..<(ProvenanceBounds.limit + 5) {
      await store.appendProvenance(entry(app: "App\(index)"), to: created.id)
    }

    let kept = await store.pads.first { $0.id == created.id }?.provenance
    #expect(kept?.count == ProvenanceBounds.limit)
    #expect(kept?.last?.sourceAppName == "App\(ProvenanceBounds.limit + 4)")
  }

  // MARK: - FR-7.3, what the list says

  @Test("Rows are newest first, because that is what the question is about")
  func newestFirst() {
    let rows = ProvenanceModel.rows(
      for: pad([entry(app: "Older", ago: 600), entry(app: "Newer", ago: 10)]), now: now)
    #expect(rows.map(\.source) == ["Newer", "Older"])
  }

  @Test("A row names the application, what arrived, and when")
  func rowContents() {
    let rows = ProvenanceModel.rows(for: pad([entry(ago: 120)]), now: now)
    let row = try? #require(rows.first)
    #expect(row?.source == "Safari")
    #expect(row?.detail == "Styled text from example.com, 2 KB")
    #expect(row?.when == "2m ago")
    #expect(row?.url?.absoluteString.contains("example.com") == true)
    #expect(row?.links.count == 1)
  }

  /// `FR-7.1`'s second half: an application supplying no URL records the
  /// application alone, without error.
  @Test("An arrival with no URL says what it knows and no more")
  func noURL() {
    let rows = ProvenanceModel.rows(for: pad([entry(url: nil, kind: .text, bytes: 40)]), now: now)
    #expect(rows.first?.detail == "Plain text, 40 bytes")
    #expect(rows.first?.url == nil)
    // Nought or one, so the view renders it with a ForEach rather than a branch.
    #expect(rows.first?.links.isEmpty == true)
  }

  @Test("An arrival from nothing identifiable still produces a readable row")
  func unknownSource() {
    let anonymous = ProvenanceEntry(arrived: now, byteCount: 10, kind: .image)
    let rows = ProvenanceModel.rows(for: pad([anonymous]), now: now)
    #expect(rows.first?.source == "An unidentified application")
    #expect(rows.first?.detail == "An image, 10 bytes")
  }

  @Test("A file shows its name; a page shows its host")
  func locations() throws {
    #expect(
      ProvenanceModel.displayLocation(URL(fileURLWithPath: "/tmp/notes.txt")) == "notes.txt")
    let page = try #require(URL(string: "https://news.example.com/x?y=1"))
    #expect(ProvenanceModel.displayLocation(page) == "news.example.com")
    // Not everything with a scheme has a host worth showing.
    let opaque = try #require(URL(string: "data:text/plain,hello"))
    #expect(ProvenanceModel.displayLocation(opaque) == nil)
  }

  @Test("Every kind of arrival has a noun")
  func nouns() {
    #expect(ProvenanceEntry.Kind.allCases.allSatisfy { !ProvenanceModel.noun(for: $0).isEmpty })
  }

  @Test("Size is coarse, and distinguishes a line from a screenshot")
  func sizes() {
    #expect(ProvenanceModel.size(0) == "0 bytes")
    #expect(ProvenanceModel.size(900) == "900 bytes")
    #expect(ProvenanceModel.size(2_048) == "2 KB")
    #expect(ProvenanceModel.size(3_145_728) == "3.0 MB")
  }

  @Test("Age is said in the units a person would use")
  func ages() {
    #expect(ProvenanceModel.age(from: now, to: now) == "just now")
    #expect(ProvenanceModel.age(from: now.addingTimeInterval(-90), to: now) == "1m ago")
    #expect(ProvenanceModel.age(from: now.addingTimeInterval(-7_200), to: now) == "2h ago")
    #expect(ProvenanceModel.age(from: now.addingTimeInterval(-172_800), to: now) == "2d ago")
    // A clock that went backwards must not produce "-3m ago".
    #expect(ProvenanceModel.age(from: now.addingTimeInterval(180), to: now) == "just now")
  }

  // MARK: - FR-7.4, the claim that is not made

  /// The requirement is that no authoritative claim is made about which text
  /// came from where. The cheapest way to honour it is to never mention a
  /// range, and this is what checks nobody has added one.
  @Test("Nothing in the presentation claims which text came from where")
  func makesNoRangeClaim() {
    let rows = ProvenanceModel.rows(for: pad([entry()]), now: now)
    let everything = rows.map { "\($0.source) \($0.detail) \($0.when)" }.joined()
      + ProvenanceModel.caption + ProvenanceModel.emptyMessage
    for word in ["character", "range", "offset", "position", "from line"] {
      #expect(!everything.lowercased().contains(word), "the list claims a \(word)")
    }
    // And it says so, where somebody reading the list will see it.
    #expect(ProvenanceModel.caption.contains("does not track which text"))
  }

  // MARK: - Wording

  @Test("An empty list explains itself rather than showing nothing")
  func emptyWording() {
    #expect(ProvenanceModel.rows(for: pad([]), now: now).isEmpty)
    #expect(ProvenanceModel.emptyMessage.contains("not what you typed"))
    #expect(ProvenanceModel.summary(count: 0) == "No arrivals recorded")
    #expect(ProvenanceModel.summary(count: 1) == "1 arrival recorded")
    #expect(ProvenanceModel.summary(count: 4) == "4 arrivals recorded")
  }

  /// A button called Clear on a pad could reasonably be read as clearing the
  /// pad, so the sheet says which it is.
  @Test("Clearing says it leaves the content alone")
  func clearWording() {
    #expect(ProvenanceModel.clearNote.contains("untouched"))
  }

  @Test("A full list says why older arrivals are missing")
  func trimmedWording() {
    #expect(ProvenanceModel.trimmedNote(count: 3) == nil)
    #expect(
      ProvenanceModel.trimmedNote(count: ProvenanceBounds.limit)?
        .contains(String(ProvenanceBounds.limit)) == true)
  }
}
