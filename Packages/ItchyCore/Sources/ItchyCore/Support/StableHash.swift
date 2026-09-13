import Foundation

/// A 64-bit FNV-1a hash that is the same in every process and on every run.
///
/// Swift's `Hasher` is seeded per process, so a value it produces cannot be
/// stored and compared after a relaunch. This is for change detection only, not
/// for anything adversarial.
public struct StableHash: Sendable {
  private var state: UInt64 = 0xcbf2_9ce4_8422_2325
  private static let prime: UInt64 = 0x0000_0100_0000_01b3

  public init() {}

  public mutating func combine(_ data: Data) {
    for byte in data {
      state ^= UInt64(byte)
      state = state &* Self.prime
    }
    // A separator, so that ("ab", "c") and ("a", "bc") hash differently.
    state ^= 0xff
    state = state &* Self.prime
  }

  public mutating func combine(_ text: String) {
    combine(Data(text.utf8))
  }

  public mutating func combine(_ number: Int) {
    combine(String(number))
  }

  public var hex: String {
    String(state, radix: 16)
  }
}
