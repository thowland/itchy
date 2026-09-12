import Foundation

/// Decodes and encodes a value while carrying unrecognised fields through
/// untouched (`FR-5.7`, specification §6.4).
///
/// Synthesised `Codable` discards what it does not know, so a hand-edited field
/// would vanish on the next save. The approach here is to decode twice — once
/// into the value, once into a dictionary — and to determine the unknown keys by
/// re-encoding the value and subtracting its own keys. Deriving the known keys
/// that way rather than from a hand-maintained list means a new property cannot
/// be forgotten here and then silently treated as an unknown field forever.
public enum PreservingCodec {
  /// A decoded value together with the fields that were present on disk but are
  /// not part of the value's own shape.
  public struct Decoded<Value: Codable & Sendable>: Sendable {
    public var value: Value
    public var unknown: [String: JSONValue]

    public init(value: Value, unknown: [String: JSONValue]) {
      self.value = value
      self.unknown = unknown
    }
  }

  public static func decode<Value: Codable & Sendable>(
    _ type: Value.Type,
    from data: Data
  ) throws -> Decoded<Value> {
    let decoder = JSONCoding.decoder()
    let value = try decoder.decode(Value.self, from: data)
    let onDisk = try decoder.decode([String: JSONValue].self, from: data)
    let known = try knownKeys(of: value)
    let unknown = onDisk.filter { !known.contains($0.key) }
    return Decoded(value: value, unknown: unknown)
  }

  public static func encode<Value: Codable & Sendable>(
    _ value: Value,
    preserving unknown: [String: JSONValue]
  ) throws -> Data {
    var merged = unknown
    for (key, encoded) in try fields(of: value) {
      merged[key] = encoded
    }
    return try JSONCoding.encoder().encode(merged)
  }

  private static func fields<Value: Codable>(of value: Value) throws -> [String: JSONValue] {
    let data = try JSONCoding.encoder().encode(value)
    return try JSONCoding.decoder().decode([String: JSONValue].self, from: data)
  }

  private static func knownKeys<Value: Codable>(of value: Value) throws -> Set<String> {
    Set(try fields(of: value).keys)
  }
}
