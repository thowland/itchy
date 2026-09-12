import Foundation

/// The single encoder and decoder configuration used for every file on disk.
///
/// Held in one place so that no two call sites can disagree about date format or
/// key order. Output is sorted and pretty-printed because these files are read by
/// people, by command-line tooling and — from R3 — by agents, and the cost of
/// formatting them legibly is nil at this scale (specification §6.2).
public enum JSONCoding {
  /// ISO 8601 in UTC with fractional seconds omitted.
  ///
  /// `ISO8601FormatStyle` rather than `ISO8601DateFormatter` because the latter
  /// is not `Sendable` and a shared instance is a data race the compiler
  /// correctly refuses under strict concurrency (D-1).
  public static let dateStyle = Date.ISO8601FormatStyle(timeZone: .gmt)

  public static func encoder() -> JSONEncoder {
    let encoder = JSONEncoder()
    encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
    encoder.dateEncodingStrategy = .custom { date, encoder in
      var container = encoder.singleValueContainer()
      try container.encode(date.formatted(Self.dateStyle))
    }
    return encoder
  }

  public static func decoder() -> JSONDecoder {
    let decoder = JSONDecoder()
    decoder.dateDecodingStrategy = .custom { decoder in
      let container = try decoder.singleValueContainer()
      let text = try container.decode(String.self)
      guard let date = try? Date(text, strategy: Self.dateStyle) else {
        throw DecodingError.dataCorruptedError(
          in: container, debugDescription: "not an ISO 8601 date: \(text)")
      }
      return date
    }
    return decoder
  }
}
