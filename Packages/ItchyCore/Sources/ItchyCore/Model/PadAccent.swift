import Foundation

/// A colour, as three components and nothing else (`FR-3.8`).
///
/// Numbers rather than an `NSColor` because `ItchyCore` links no UI framework
/// (D-2, `NFR-4.3`), and because the thing that has to survive a save is the
/// colour itself rather than a particular framework's idea of it.
public struct AccentRGB: Sendable, Equatable, Codable {
  /// Each component runs 0…1 and is clamped on the way in, so a hand-edited
  /// file cannot produce a colour the drawing layer has to defend itself from.
  public let red: Double
  public let green: Double
  public let blue: Double

  public init(red: Double, green: Double, blue: Double) {
    self.red = AccentRGB.clamped(red)
    self.green = AccentRGB.clamped(green)
    self.blue = AccentRGB.clamped(blue)
  }

  private static func clamped(_ value: Double) -> Double {
    min(max(value, 0), 1)
  }
}

/// The palette's colours, by name (`FR-3.8`).
///
/// A closed set, because the rule is a landmark rather than a label. Six is
/// enough to tell a handful of pads apart at a glance and few enough that
/// nobody is choosing a taxonomy.
public enum PadAccentName: String, Sendable, Equatable, Codable, CaseIterable {
  case slate
  case sky
  case moss
  case amber
  case clay
  case plum
}

/// What a pad's accent rule is set to (`FR-3.8`).
///
/// `nil` on the pad rather than a `.none` case here: a pad with no rule has no
/// accent, and the absence is the default that every existing pad already has
/// on disk.
public enum PadAccent: Sendable, Equatable {
  case named(PadAccentName)
  case custom(AccentRGB)
}

// MARK: - On disk

/// Written as one string — `"sky"` or `"#4A90D9"` — rather than as the nested
/// object a synthesised `Codable` would produce for an enum with associated
/// values.
///
/// `FR-5.7` says a pad's metadata is hand-editable and that unrecognised fields
/// survive a save. A field somebody may reasonably want to edit by hand should
/// be legible when they open the file, and `{"named":{"_0":"sky"}}` is not.
extension PadAccent: Codable {
  public init(from decoder: Decoder) throws {
    let token = try decoder.singleValueContainer().decode(String.self)
    guard let accent = PadAccent(token: token) else {
      throw DecodingError.dataCorrupted(
        DecodingError.Context(
          codingPath: decoder.codingPath,
          debugDescription: "\"\(token)\" is neither a palette name nor a #rrggbb colour"))
    }
    self = accent
  }

  public func encode(to encoder: Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(token)
  }

  /// What this accent is written as.
  public var token: String {
    switch self {
    case .named(let name):
      return name.rawValue
    case .custom(let rgb):
      return PadAccent.hex(rgb)
    }
  }

  /// Reads what `token` wrote. Returns nil rather than throwing so that the
  /// parse can be tested as a function and reused where a failure is not fatal.
  public init?(token: String) {
    let trimmed = token.trimmingCharacters(in: .whitespaces).lowercased()
    if let name = PadAccentName(rawValue: trimmed) {
      self = .named(name)
      return
    }
    guard let rgb = PadAccent.rgb(hex: trimmed) else { return nil }
    self = .custom(rgb)
  }

  private static func hex(_ rgb: AccentRGB) -> String {
    let byte = { (component: Double) in Int((component * 255).rounded()) }
    return String(format: "#%02x%02x%02x", byte(rgb.red), byte(rgb.green), byte(rgb.blue))
  }

  private static func rgb(hex: String) -> AccentRGB? {
    var digits = hex
    if digits.hasPrefix("#") { digits.removeFirst() }
    guard digits.count == 6, let value = Int(digits, radix: 16) else { return nil }
    return AccentRGB(
      red: Double((value >> 16) & 0xff) / 255,
      green: Double((value >> 8) & 0xff) / 255,
      blue: Double(value & 0xff) / 255)
  }
}

// MARK: - The palette

/// What each named colour actually is, in each appearance (`FR-3.8`).
///
/// Two values per name because a rule dark enough to read against a white pad
/// disappears against a dark one, and a rule chosen for a dark pad glares on a
/// light one. The palette is muted on purpose: this marks a window, it does not
/// decorate it.
///
/// A custom colour has one value and is returned unchanged in both appearances.
/// That is the cost of choosing a colour outside the palette, and it is stated
/// where the choice is offered rather than discovered later in the dark.
public enum PadAccentPalette {
  public enum Appearance: Sendable, Equatable, CaseIterable {
    case light
    case dark
  }

  public static func rgb(of accent: PadAccent, in appearance: Appearance) -> AccentRGB {
    switch accent {
    case .custom(let rgb):
      return rgb
    case .named(let name):
      return appearance == .light ? light(name) : dark(name)
    }
  }

  /// How thick the rule is drawn, in points. Three is enough to read as a
  /// deliberate band rather than as a border the window happens to have, and
  /// thin enough not to cost the editor a visible amount of height.
  public static let thickness: Double = 3

  private static func light(_ name: PadAccentName) -> AccentRGB {
    switch name {
    case .slate: return rgb(0x5B, 0x6B, 0x7C)
    case .sky: return rgb(0x3E, 0x7C, 0xB1)
    case .moss: return rgb(0x5C, 0x8A, 0x5C)
    case .amber: return rgb(0xB8, 0x86, 0x3B)
    case .clay: return rgb(0xB0, 0x5C, 0x4A)
    case .plum: return rgb(0x7B, 0x5C, 0x9E)
    }
  }

  private static func dark(_ name: PadAccentName) -> AccentRGB {
    switch name {
    case .slate: return rgb(0x8A, 0x9B, 0xAC)
    case .sky: return rgb(0x6F, 0xA8, 0xD6)
    case .moss: return rgb(0x86, 0xB6, 0x86)
    case .amber: return rgb(0xD8, 0xAC, 0x63)
    case .clay: return rgb(0xD1, 0x8A, 0x76)
    case .plum: return rgb(0xA9, 0x8C, 0xC4)
    }
  }

  private static func rgb(_ red: Int, _ green: Int, _ blue: Int) -> AccentRGB {
    AccentRGB(
      red: Double(red) / 255, green: Double(green) / 255, blue: Double(blue) / 255)
  }
}
