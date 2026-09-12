import Foundation

/// A pad's stable identity, and the name of its directory on disk.
public struct PadID: Hashable, Sendable, Codable, CustomStringConvertible {
  public let rawValue: UUID

  public init(rawValue: UUID = UUID()) {
    self.rawValue = rawValue
  }

  public init?(string: String) {
    guard let uuid = UUID(uuidString: string) else { return nil }
    self.rawValue = uuid
  }

  public var description: String {
    rawValue.uuidString
  }

  /// The directory name for this pad under `pads/` (specification §6.1).
  public var directoryName: String {
    rawValue.uuidString
  }

  public init(from decoder: any Decoder) throws {
    let text = try decoder.singleValueContainer().decode(String.self)
    guard let uuid = UUID(uuidString: text) else {
      throw DecodingError.dataCorruptedError(
        in: try decoder.singleValueContainer(),
        debugDescription: "not a UUID: \(text)")
    }
    self.rawValue = uuid
  }

  public func encode(to encoder: any Encoder) throws {
    var container = encoder.singleValueContainer()
    try container.encode(rawValue.uuidString)
  }
}
