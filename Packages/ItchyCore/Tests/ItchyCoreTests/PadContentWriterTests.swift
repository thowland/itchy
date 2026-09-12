import Foundation
import Testing

@testable import ItchyCore

@Suite("Pad sizes and emptying")
struct PadSizeTests {
  @Test("Sizes are reported for every pad (FR-5.9)")
  func sizes() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    let small = try await store.createPad(name: "small")
    let large = try await store.createPad(name: "large")
    await store.stage(
      PadContent(bundle: ["TXT.rtf": Data(repeating: 0x41, count: 200_000)], plainText: "x"),
      for: large.id, origin: .user)
    try await store.flushAll()

    let sizes = await store.sizes()

    #expect(sizes[small.id] ?? 0 > 0)
    #expect((sizes[large.id] ?? 0) > (sizes[small.id] ?? 0))
  }

  /// `FR-2.6`: emptying is a single action, and one undo restores the content
  /// while the panel is open.
  @Test("Emptying a pad clears its content but keeps the pad")
  func emptying() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    let pad = try await store.createPad(name: "keeper")
    await store.stage(PadContent.plainText("some content"), for: pad.id, origin: .user)
    try await store.flush(pad.id)

    try await store.empty(pad.id)

    #expect(try await store.content(of: pad.id).plainText.isEmpty)
    #expect(await store.pads.count == 1, "emptying is not deleting")
  }

  @Test("Emptying an unknown pad throws rather than doing nothing quietly")
  func emptyingGhost() async throws {
    let root = TemporaryRoot()
    let store = PadStore(layout: root.layout, now: FixedClock().now)
    await store.load()
    let ghost = PadID()
    await #expect(throws: PadStoreFault.unknownPad(ghost)) {
      try await store.empty(ghost)
    }
  }
}

@Suite("Plain-text RTF writer")
struct PlainTextRTFTests {
  /// Found by taking a screenshot for the README: an em dash came back as
  /// `â€"`. An `\ansi` document's bytes are read as cp1252, so raw UTF-8 is
  /// corrupted and non-ASCII must be escaped as `\uN?`.
  @Test(
    "Non-ASCII characters are escaped rather than written as raw bytes",
    arguments: [
      "an em dash — like that",
      "naïve café",
      "→ arrows ←",
      "日本語",
      "emoji 🐈 survive",
    ])
  func nonASCIIIsEscaped(text: String) throws {
    let content = PadContent.plainText(text)
    let document = try #require(content.document)
    let rtf = try #require(String(bytes: document, encoding: .utf8))

    #expect(rtf.contains("\\u"), "non-ASCII must be escaped for an \\ansi document")
    #expect(content.plainText == text, "the shadow text keeps the original")

    // Nothing non-ASCII may reach the document as a raw byte.
    let isPureASCII = rtf.allSatisfy(\.isASCII)
    #expect(isPureASCII, "the RTF document must be pure ASCII")
  }

  @Test("ASCII text is written directly, without escaping noise")
  func asciiIsUntouched() throws {
    let document = try #require(PadContent.plainText("plain ascii text").document)
    let rtf = try #require(String(bytes: document, encoding: .utf8))
    #expect(rtf.contains("plain ascii text"))
    #expect(!rtf.contains("\\u"))
  }

  @Test("RTF control characters are still escaped")
  func controlCharacters() throws {
    let document = try #require(PadContent.plainText(#"a \ b { c }"#).document)
    let rtf = try #require(String(bytes: document, encoding: .utf8))
    #expect(rtf.contains(#"\\"#))
    #expect(rtf.contains(#"\{"#))
    #expect(rtf.contains(#"\}"#))
  }
}
