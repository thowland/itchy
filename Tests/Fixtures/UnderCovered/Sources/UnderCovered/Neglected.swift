import Foundation

/// One covered function and a great many uncovered ones.
public enum Neglected {
  public static func covered(_ value: Int) -> Int {
    value + 1
  }

  public static func uncoveredA(_ value: Int) -> Int {
    let doubled = value * 2
    let offset = doubled - 3
    return offset * offset
  }

  public static func uncoveredB(_ text: String) -> String {
    let trimmed = text.trimmingCharacters(in: .whitespaces)
    let upper = trimmed.uppercased()
    return upper + "!"
  }

  public static func uncoveredC(_ values: [Int]) -> Int {
    let total = values.reduce(0, +)
    let scaled = total * 7
    return scaled
  }
}
