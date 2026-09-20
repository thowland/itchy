import Foundation
import Testing

@testable import ItchyCore

/// The accent rule as data (`FR-3.8`, D-33).
@Suite("Pad accent")
struct PadAccentTests {
  // MARK: - What it is written as

  /// One string, because `FR-5.7` says somebody may open this file and edit it.
  @Test("A palette colour is written as its name")
  func namedToken() {
    #expect(PadAccent.named(.sky).token == "sky")
    #expect(PadAccent(token: "sky") == .named(.sky))
  }

  @Test("A custom colour is written as #rrggbb")
  func customToken() {
    let accent = PadAccent.custom(AccentRGB(red: 1, green: 0, blue: 0.5))
    #expect(accent.token == "#ff0080")
    // Through the token rather than against the original: the form stores a
    // byte per component, so 0.5 comes back as 128/255. Reading what was
    // written is the property that matters, and it holds.
    #expect(PadAccent(token: accent.token)?.token == accent.token)
  }

  /// Hand-editing is the whole reason the format is a string, so the reader has
  /// to tolerate what a person types rather than only what the writer emits.
  @Test("Case, surrounding space and a missing # are not part of the value")
  func tolerantParsing() {
    #expect(PadAccent(token: "  SKY ") == .named(.sky))
    #expect(PadAccent(token: "#FF0080") == PadAccent(token: "#ff0080"))
    // Somebody copying a colour out of a design tool gets it without the hash
    // as often as with it, and no palette name is six hex digits long.
    #expect(PadAccent(token: "ff0080") == PadAccent(token: "#ff0080"))
  }

  @Test("Anything that is neither a name nor a colour is refused")
  func rejectsNonsense() {
    for token in ["", "turquoise", "#ff", "#gggggg", "#ff00800", "#"] {
      #expect(PadAccent(token: token) == nil, "\"\(token)\" was accepted")
    }
  }

  @Test("Every palette colour survives being written and read back")
  func namedRoundTrip() throws {
    for name in PadAccentName.allCases {
      let accent = PadAccent.named(name)
      let data = try JSONEncoder().encode(accent)
      #expect(String(data: data, encoding: .utf8) == "\"\(name.rawValue)\"")
      #expect(try JSONDecoder().decode(PadAccent.self, from: data) == accent)
    }
  }

  /// Within the rounding the hex form imposes, which is a byte per component.
  @Test("A custom colour survives being written and read back")
  func customRoundTrip() throws {
    let accent = PadAccent.custom(AccentRGB(red: 0.2, green: 0.4, blue: 0.6))
    let decoded = try JSONDecoder().decode(
      PadAccent.self, from: try JSONEncoder().encode(accent))
    guard case .custom(let rgb) = decoded else {
      Issue.record("a custom colour decoded as something else")
      return
    }
    #expect(abs(rgb.red - 0.2) < 0.01)
    #expect(abs(rgb.green - 0.4) < 0.01)
    #expect(abs(rgb.blue - 0.6) < 0.01)
  }

  @Test("A corrupt accent is a decoding error rather than a silent default")
  func refusesCorruptAccent() {
    #expect(throws: DecodingError.self) {
      try JSONDecoder().decode(PadAccent.self, from: Data("\"turquoise\"".utf8))
    }
  }

  // MARK: - Components

  /// A hand-edited file is the input here, and a component outside 0…1 would
  /// otherwise reach the drawing layer.
  @Test("Components are clamped to 0…1")
  func clampsComponents() {
    let rgb = AccentRGB(red: -3, green: 0.5, blue: 40)
    #expect(rgb.red == 0)
    #expect(rgb.green == 0.5)
    #expect(rgb.blue == 1)
  }

  // MARK: - The palette

  /// The rule has to be visible on a white pad and on a dark one, so the two
  /// values differ for every name. Equal values would mean one appearance was
  /// forgotten, which is invisible until somebody switches.
  @Test("Every palette colour has a different value in each appearance")
  func lightAndDarkDiffer() {
    for name in PadAccentName.allCases {
      let light = PadAccentPalette.rgb(of: .named(name), in: .light)
      let dark = PadAccentPalette.rgb(of: .named(name), in: .dark)
      #expect(light != dark, "\(name) is the same colour in both appearances")
    }
  }

  /// Six landmarks are only six landmarks if they are distinguishable.
  @Test("No two palette colours are the same")
  func paletteIsDistinct() {
    for appearance in PadAccentPalette.Appearance.allCases {
      let colours = PadAccentName.allCases.map {
        PadAccentPalette.rgb(of: .named($0), in: appearance)
      }
      #expect(Set(colours.map(\.description)).count == PadAccentName.allCases.count)
    }
  }

  /// Stated where the choice is offered, and asserted here so the statement
  /// cannot quietly stop being true.
  @Test("A custom colour is the same in both appearances")
  func customDoesNotAdapt() {
    let accent = PadAccent.custom(AccentRGB(red: 0.1, green: 0.2, blue: 0.3))
    #expect(
      PadAccentPalette.rgb(of: accent, in: .light)
        == PadAccentPalette.rgb(of: accent, in: .dark))
  }

  // MARK: - On a pad

  @Test("A pad has no accent until one is set")
  func defaultsToNoAccent() {
    #expect(PadMetadata.newPad(name: "Notes", now: Date()).accent == nil)
  }

  /// The reason the field is optional: every pad already on disk was written
  /// without it, and those files are not rewritten on upgrade.
  ///
  /// Built by taking the key back out of what the encoder produces rather than
  /// by hand, so this tests the shape the previous version actually wrote
  /// instead of the shape I remember it writing.
  @Test("Metadata written before the field existed still decodes")
  func decodesOlderMetadata() throws {
    let pad = PadMetadata.newPad(name: "Notes", now: Date())
    var object = try JSONCoding.decoder().decode(
      [String: JSONValue].self,
      from: try JSONCoding.encoder().encode(
        PadMetadata(
          id: pad.id, name: pad.name, created: pad.created, modified: pad.modified,
          accent: .named(.sky))))
    #expect(object["accent"] != nil)

    object["accent"] = nil
    let decoded = try JSONCoding.decoder().decode(
      PadMetadata.self, from: try JSONCoding.encoder().encode(object))
    #expect(decoded.accent == nil)
    #expect(decoded.name == "Notes")
  }
}

extension AccentRGB {
  fileprivate var description: String { "\(red),\(green),\(blue)" }
}
