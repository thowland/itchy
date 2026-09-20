import AppKit
import ItchyCore
import SwiftUI
import Testing

@testable import Itchy

/// The accent control's decisions (`FR-3.8`, D-33, D-11).
@Suite("Pad accent control")
struct PadAccentModelTests {
  // MARK: - Rows

  /// None, then the palette, then custom. The count matters as much as the
  /// order: a palette colour added without a row here would be unreachable.
  @Test("Every palette colour has a row, with none first and custom last")
  func rows() {
    #expect(PadAccentModel.all.count == PadAccentName.allCases.count + 2)
    #expect(PadAccentModel.all.first == PadAccentChoice.none)
    #expect(PadAccentModel.all.last == PadAccentChoice.custom)
    for name in PadAccentName.allCases {
      #expect(PadAccentModel.all.contains(.named(name)), "\(name) has no row")
    }
  }

  @Test("Each accent selects its own row")
  func selection() {
    #expect(PadAccentModel.choice(for: nil) == .none)
    #expect(PadAccentModel.choice(for: .named(.moss)) == .named(.moss))
    #expect(
      PadAccentModel.choice(for: .custom(AccentRGB(red: 0, green: 0, blue: 1))) == .custom)
  }

  @Test("Every row has a label, and none of them are empty")
  func labels() {
    for choice in PadAccentModel.all {
      #expect(!PadAccentModel.title(choice).isEmpty)
    }
    #expect(PadAccentModel.title(.none) == "None")
    #expect(PadAccentModel.title(.named(.sky)) == "Sky")
  }

  // MARK: - What a row does

  @Test("Choosing none turns the rule off")
  func choosingNone() {
    #expect(PadAccentModel.accent(for: .none, current: .named(.clay)) == nil)
  }

  @Test("Choosing a palette colour sets that colour")
  func choosingNamed() {
    #expect(PadAccentModel.accent(for: .named(.plum), current: nil) == .named(.plum))
  }

  /// Leaving the picker and coming back must not discard a colour somebody
  /// chose, which is what re-seeding on every selection would do.
  @Test("Choosing custom again keeps the colour already chosen")
  func customIsSticky() {
    let chosen = PadAccent.custom(AccentRGB(red: 0.9, green: 0.1, blue: 0.4))
    #expect(PadAccentModel.accent(for: .custom, current: chosen) == chosen)
  }

  /// Opening the well at black would read as a broken control rather than as
  /// an empty one.
  @Test("Arriving at custom from a palette colour seeds the well with it")
  func customSeedsFromPalette() {
    let seeded = PadAccentModel.accent(for: .custom, current: .named(.amber))
    #expect(seeded == .custom(PadAccentPalette.rgb(of: .named(.amber), in: .light)))
  }

  @Test("Arriving at custom from no accent still seeds a visible colour")
  func customSeedsFromNothing() {
    guard case .custom(let rgb) = PadAccentModel.accent(for: .custom, current: nil) else {
      Issue.record("custom did not produce a custom accent")
      return
    }
    #expect(rgb != AccentRGB(red: 0, green: 0, blue: 0))
  }

  // MARK: - What is said and shown

  @Test("The well is shown for a custom colour and for nothing else")
  func wellVisibility() {
    #expect(!PadAccentModel.showsColorWell(for: nil))
    #expect(!PadAccentModel.showsColorWell(for: .named(.sky)))
    #expect(PadAccentModel.showsColorWell(for: .custom(AccentRGB(red: 1, green: 1, blue: 1))))
  }

  /// The limitation is stated where the choice is made, not discovered at dusk.
  @Test("Only a custom colour carries a note, and it mentions both appearances")
  func note() {
    #expect(PadAccentModel.note(for: nil) == nil)
    #expect(PadAccentModel.note(for: .named(.moss)) == nil)
    let note = PadAccentModel.note(for: .custom(AccentRGB(red: 0, green: 0, blue: 0)))
    #expect(note?.contains("dark") == true)
  }

  // MARK: - Appearance

  @Test("Dark appearances take the dark palette and everything else the light")
  func appearanceMapping() throws {
    let dark = try #require(NSAppearance(named: .darkAqua))
    let light = try #require(NSAppearance(named: .aqua))
    #expect(PadAccentModel.appearance(of: dark) == .dark)
    #expect(PadAccentModel.appearance(of: light) == .light)
  }

  /// A vibrant or high-contrast appearance is named neither `.aqua` nor
  /// `.darkAqua`, so a name comparison would silently send it to the light
  /// palette and a dark pad would get a colour meant for a white one.
  @Test("A vibrant dark appearance is still dark")
  func vibrantAppearance() throws {
    let vibrant = try #require(NSAppearance(named: .vibrantDark))
    #expect(PadAccentModel.appearance(of: vibrant) == .dark)
  }

  // MARK: - Colours

  /// What the well hands back can be in any colour space; the file stores three
  /// numbers with none attached, so the conversion has to pin one.
  @Test("A colour round-trips through the well's conversion")
  func colourRoundTrip() throws {
    let original = AccentRGB(red: 0.25, green: 0.5, blue: 0.75)
    let returned = try #require(AccentColorCodec.rgb(AccentColorCodec.swiftUIColor(original)))
    #expect(abs(returned.red - original.red) < 0.01)
    #expect(abs(returned.green - original.green) < 0.01)
    #expect(abs(returned.blue - original.blue) < 0.01)
  }

  @Test("A named colour resolves to a colour rather than to nothing")
  func dynamicColour() {
    for name in PadAccentName.allCases {
      #expect(AccentColorCodec.dynamicColor(for: .named(name)) != Color.clear)
    }
  }
}
