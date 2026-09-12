import Foundation
import Testing

@testable import ItchyCore

@Suite("JSON coding")
struct CodingTests {
  @Test("Metadata round-trips through the shared coder")
  func metadataRoundTrip() throws {
    let original = PadMetadata(
      id: PadID(),
      name: "scratch",
      mode: .plain,
      created: FixedClock().instant,
      modified: FixedClock().instant,
      frame: PadFrame(x: 12, y: 34, width: 420, height: 560, displayID: 1),
      isPinned: true,
      provenance: [
        ProvenanceEntry(
          arrived: FixedClock().instant,
          sourceBundleID: "com.apple.Safari",
          sourceAppName: "Safari",
          sourceURL: URL(string: "https://example.invalid/orders/88121"),
          approximateRange: 0..<412,
          byteCount: 412,
          kind: .styledText)
      ],
      isExposedToMCP: true,
      routingPolicy: .remotePermitted,
      lastOpened: FixedClock().instant,
      externalWriteMarker: ExternalWriteMarker(
        at: FixedClock().instant, origin: .mcp(client: "claude"), characterDelta: 17))

    let data = try JSONCoding.encoder().encode(original)
    let decoded = try JSONCoding.decoder().decode(PadMetadata.self, from: data)
    #expect(decoded == original)
  }

  @Test("Output is sorted so that files diff cleanly")
  func outputIsSorted() throws {
    let data = try JSONCoding.encoder().encode(
      PadIndex(order: [PadID(), PadID()], lastOpened: nil))
    let text = try #require(String(bytes: data, encoding: .utf8))
    let orderAt = try #require(text.range(of: "\"order\""))
    let versionAt = try #require(text.range(of: "\"schemaVersion\""))
    #expect(orderAt.lowerBound < versionAt.lowerBound)
  }

  @Test("Dates are ISO 8601 in UTC without fractional seconds")
  func dateFormat() throws {
    let meta = PadMetadata(
      name: "x", created: FixedClock().instant, modified: FixedClock().instant)
    let encoded = try JSONCoding.encoder().encode(meta)
    let text = try #require(String(bytes: encoded, encoding: .utf8))
    #expect(text.contains("2026-09-12T12:00:00Z"))
    #expect(!text.contains("."))
  }

  @Test("An invalid date is a decode failure, not a silent default")
  func invalidDate() throws {
    let json = """
      {
        "schemaVersion": 1, "id": "\(UUID().uuidString)", "name": "x",
        "mode": "styled", "created": "not-a-date",
        "modified": "2026-09-12T12:00:00Z", "isPinned": false,
        "provenance": [], "isExposedToMCP": false, "routingPolicy": "localOnly"
      }
      """
    #expect(throws: (any Error).self) {
      try JSONCoding.decoder().decode(PadMetadata.self, from: Data(json.utf8))
    }
  }

  @Test("A pad identifier that is not a UUID is refused")
  func badIdentifier() {
    #expect(PadID(string: "not-a-uuid") == nil)
    #expect(PadID(string: UUID().uuidString) != nil)
  }
}

@Suite("Unknown-field preservation")
struct PreservationTests {
  /// `FR-5.7`: a field added by hand must survive the next save. Synthesised
  /// `Codable` discards what it does not know, which is why §6.4 exists.
  @Test("A hand-added field survives a decode and re-encode")
  func unknownFieldSurvives() throws {
    let id = PadID()
    let json = """
      {
        "schemaVersion": 1,
        "id": "\(id)",
        "name": "scratch",
        "mode": "styled",
        "created": "2026-09-12T12:00:00Z",
        "modified": "2026-09-12T12:00:00Z",
        "isPinned": false,
        "provenance": [],
        "isExposedToMCP": false,
        "routingPolicy": "localOnly",
        "somethingAFutureBuildAdded": { "nested": [1, 2, 3] },
        "aFlagWeDoNotKnow": true
      }
      """

    let decoded = try PreservingCodec.decode(PadMetadata.self, from: Data(json.utf8))
    #expect(decoded.value.name == "scratch")
    #expect(decoded.unknown.keys.sorted() == ["aFlagWeDoNotKnow", "somethingAFutureBuildAdded"])

    var changed = decoded.value
    changed.name = "renamed"
    let reencoded = try PreservingCodec.encode(changed, preserving: decoded.unknown)
    let object = try JSONCoding.decoder().decode([String: JSONValue].self, from: reencoded)

    #expect(object["name"] == .string("renamed"))
    #expect(object["aFlagWeDoNotKnow"] == .bool(true))
    #expect(
      object["somethingAFutureBuildAdded"]
        == .object(["nested": .array([.number(1), .number(2), .number(3)])]))
  }

  @Test("Known fields take the value's version, not the file's")
  func knownFieldsWin() throws {
    let id = PadID()
    let json = """
      {"schemaVersion":1,"id":"\(id)","name":"onDisk","mode":"styled",
       "created":"2026-09-12T12:00:00Z","modified":"2026-09-12T12:00:00Z",
       "isPinned":false,"provenance":[],"isExposedToMCP":false,
       "routingPolicy":"localOnly"}
      """
    let decoded = try PreservingCodec.decode(PadMetadata.self, from: Data(json.utf8))
    var changed = decoded.value
    changed.name = "inMemory"
    let data = try PreservingCodec.encode(changed, preserving: decoded.unknown)
    let object = try JSONCoding.decoder().decode([String: JSONValue].self, from: data)
    #expect(object["name"] == .string("inMemory"))
  }

  @Test(
    "Every JSON shape survives the round trip",
    arguments: [
      JSONValue.null,
      .bool(true),
      .number(42),
      .number(-1.5),
      .string("text"),
      .array([.number(1), .string("two"), .null]),
      .object(["a": .bool(false), "b": .array([])]),
    ])
  func jsonValueRoundTrip(value: JSONValue) throws {
    let data = try JSONCoding.encoder().encode(["v": value])
    let back = try JSONCoding.decoder().decode([String: JSONValue].self, from: data)
    #expect(back["v"] == value)
  }
}
