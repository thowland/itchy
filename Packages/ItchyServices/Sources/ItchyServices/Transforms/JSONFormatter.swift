import Foundation

/// Reformats JSON text without reparsing it into a model.
///
/// `JSONSerialization` and `JSONValue` both hold objects in a dictionary, which
/// loses key order, and both round-trip numbers through `Double`, which turns
/// `1.0` into `1` and quietly loses precision on integers past 2^53. Since §7.2
/// requires that `json.pretty` preserves key order, and since someone
/// pretty-printing a payload wants their own bytes back rather than a
/// re-encoding of them, this works at the token level instead: it validates the
/// grammar as it walks, copies every scalar through verbatim, and changes only
/// the whitespace between tokens.
///
/// The same walk answers "is this JSON?", so `Transform.applicability` and
/// `apply` cannot disagree about what parses.
public enum JSONFormatter {
  public enum Style: Sendable, Equatable {
    /// Two-space indent, one element per line (§7.2).
    case pretty
    /// No whitespace between tokens at all.
    case minified
  }

  /// Why the text is not JSON, in a sentence fit to show someone, naming the
  /// offset so that a large payload's one bad character can be found.
  public struct Failure: Error, Sendable, Equatable {
    public let reason: String
    public let offset: Int

    public var message: String { "\(reason) at character \(offset)" }
  }

  public static func format(_ text: String, style: Style) throws -> String {
    var scanner = Scanner(characters: Array(text))
    var output = ""
    output.reserveCapacity(text.count)
    scanner.skipWhitespace()
    try scanner.writeValue(into: &output, style: style, depth: 0)
    scanner.skipWhitespace()
    guard scanner.isAtEnd else {
      throw scanner.failure("unexpected text after the top-level value")
    }
    return output
  }

  /// Whether the text parses, without building the reformatted output.
  public static func isValid(_ text: String) -> Bool {
    (try? format(text, style: .minified)) != nil
  }
}

extension JSONFormatter {
  /// An object's braces or an array's brackets. A pair, so that the routine
  /// that writes both takes one parameter for them rather than two.
  fileprivate struct Brackets {
    let open: Character
    let close: Character

    static let object = Brackets(open: "{", close: "}")
    static let array = Brackets(open: "[", close: "]")
  }

  /// A cursor over the source characters. A struct with a mutating index rather
  /// than a class, so that a half-finished walk cannot be shared.
  fileprivate struct Scanner {
    let characters: [Character]
    var index = 0

    var isAtEnd: Bool { index >= characters.count }
    var current: Character? { isAtEnd ? nil : characters[index] }

    func failure(_ reason: String) -> Failure {
      Failure(reason: reason, offset: index)
    }

    /// JSON's four whitespace characters, and only those.
    private static let whitespace: Set<Character> = [" ", "\n", "\r", "\t"]

    mutating func skipWhitespace() {
      while let character = current, Self.whitespace.contains(character) {
        index += 1
      }
    }

    mutating func take(_ expected: Character) throws {
      guard current == expected else {
        throw failure("expected '\(expected)'")
      }
      index += 1
    }

    mutating func writeValue(into output: inout String, style: Style, depth: Int) throws {
      switch current {
      case "{": try writeObject(into: &output, style: style, depth: depth)
      case "[": try writeArray(into: &output, style: style, depth: depth)
      case "\"": try writeString(into: &output)
      case .none: throw failure("the text ends where a value was expected")
      default: try writeLiteral(into: &output)
      }
    }

    /// Objects and arrays differ only in their brackets and in whether each
    /// element carries a key, so one routine writes both and the two callers
    /// supply the difference.
    private mutating func writeContainer(
      into output: inout String,
      style: Style,
      depth: Int,
      brackets: Brackets,
      element: (inout Scanner, inout String) throws -> Void
    ) throws {
      let (open, close) = (brackets.open, brackets.close)
      try take(open)
      output.append(open)
      skipWhitespace()
      if current == close {
        index += 1
        output.append(close)
        return
      }
      var isFirst = true
      while true {
        if !isFirst {
          try take(",")
          output.append(",")
        }
        isFirst = false
        writeBreak(into: &output, style: style, depth: depth + 1)
        skipWhitespace()
        try element(&self, &output)
        skipWhitespace()
        if current == close { break }
        guard current == "," else {
          throw failure("expected ',' or '\(close)'")
        }
      }
      try take(close)
      writeBreak(into: &output, style: style, depth: depth)
      output.append(close)
    }

    private mutating func writeObject(into output: inout String, style: Style, depth: Int) throws {
      try writeContainer(into: &output, style: style, depth: depth, brackets: .object) { scanner, output in
        guard scanner.current == "\"" else {
          throw scanner.failure("expected a quoted key")
        }
        try scanner.writeString(into: &output)
        scanner.skipWhitespace()
        try scanner.take(":")
        output.append(style == .pretty ? ": " : ":")
        scanner.skipWhitespace()
        try scanner.writeValue(into: &output, style: style, depth: depth + 1)
      }
    }

    private mutating func writeArray(into output: inout String, style: Style, depth: Int) throws {
      try writeContainer(into: &output, style: style, depth: depth, brackets: .array) { scanner, output in
        try scanner.writeValue(into: &output, style: style, depth: depth + 1)
      }
    }

    private func writeBreak(into output: inout String, style: Style, depth: Int) {
      guard style == .pretty else { return }
      output.append("\n")
      output.append(String(repeating: "  ", count: depth))
    }

    /// Copies the string through verbatim, escapes and all, having checked that
    /// every escape is one JSON allows.
    mutating func writeString(into output: inout String) throws {
      try take("\"")
      output.append("\"")
      while let character = current {
        index += 1
        output.append(character)
        if character == "\"" { return }
        guard character == "\\" else { continue }
        guard let escaped = current else { break }
        guard "\"\\/bfnrtu".contains(escaped) else {
          throw failure("'\\\(escaped)' is not a valid escape")
        }
        index += 1
        output.append(escaped)
        guard escaped == "u" else { continue }
        try writeHexQuad(into: &output)
      }
      throw failure("the text ends inside a string")
    }

    private mutating func writeHexQuad(into output: inout String) throws {
      for _ in 0..<4 {
        guard let digit = current, digit.isHexDigit else {
          throw failure("\\u needs four hexadecimal digits")
        }
        index += 1
        output.append(digit)
      }
    }

    /// Numbers, `true`, `false` and `null`. Copied through unchanged, so a
    /// number keeps the spelling it was written with.
    mutating func writeLiteral(into output: inout String) throws {
      let start = index
      while let character = current, !",]}: \n\r\t".contains(character) {
        index += 1
      }
      let literal = String(characters[start..<index])
      guard Self.isLiteral(literal) else {
        throw Failure(reason: "'\(literal)' is not a valid JSON value", offset: start)
      }
      output.append(literal)
    }

    private static func isLiteral(_ literal: String) -> Bool {
      if literal == "true" || literal == "false" || literal == "null" { return true }
      return isNumber(literal)
    }

    /// JSON's number grammar, which is stricter than `Double(_:)`: no leading
    /// plus, no leading zero on a multi-digit integer part, no hexadecimal, no
    /// `inf` or `nan`, and a decimal point must have a digit on each side.
    private static func isNumber(_ literal: String) -> Bool {
      var rest = Substring(literal)
      if rest.first == "-" { rest = rest.dropFirst() }
      guard let integer = takeDigits(&rest), integer == "0" ? true : integer.first != "0" else {
        return false
      }
      if rest.first == "." {
        rest = rest.dropFirst()
        guard takeDigits(&rest) != nil else { return false }
      }
      if rest.first == "e" || rest.first == "E" {
        rest = rest.dropFirst()
        if rest.first == "+" || rest.first == "-" { rest = rest.dropFirst() }
        guard takeDigits(&rest) != nil else { return false }
      }
      return rest.isEmpty
    }

    private static func takeDigits(_ rest: inout Substring) -> Substring? {
      let digits = rest.prefix { $0.isASCII && $0.isNumber }
      guard !digits.isEmpty else { return nil }
      rest = rest.dropFirst(digits.count)
      return digits
    }
  }
}
