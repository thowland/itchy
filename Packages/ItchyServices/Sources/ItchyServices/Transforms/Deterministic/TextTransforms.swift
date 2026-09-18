import Foundation
import ItchyCore

/// Shared predicate for the transforms §7.2 describes as taking "any text".
///
/// Any text still means some text: offering "Sort lines" on an empty pad is
/// noise, and a transform that succeeds by doing nothing is worse than one that
/// declines. Whitespace-only counts as empty for the same reason, except for
/// `whitespace.trim`, which is precisely the transform that has something to do
/// with it.
internal enum TextPredicate {
  internal static func hasText(_ input: TransformInput) -> Applicability {
    guard !input.plainText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else {
      return .notApplicable(reason: "There is no text to transform.")
    }
    return .applicable
  }
}

/// Drops styling, keeping the characters (`FR-4.5`, §7.2).
///
/// Shares its meaning with the mode switch rather than its code: flattening is
/// "keep the string, drop the attributes", and the attributed-string half of
/// that lives in the app's `ContentCodec` because it needs AppKit to know what a
/// font is. Here the string is already plain, so the transform returns it and
/// the applier restyles to the pad's body font.
public struct FlattenTransform: Transform {
  public let id = "flatten"
  public let title = "Flatten Styling"
  public let requiresNetwork = false

  public init() {}

  public func applicability(to input: TransformInput) -> Applicability {
    guard input.padMode == .styled else {
      return .notApplicable(reason: "This pad already holds plain text.")
    }
    return TextPredicate.hasText(input)
  }

  public func apply(to input: TransformInput) async throws -> TransformOutput {
    .plainText(input.plainText)
  }
}

/// Upper, lower and title case (§7.2).
public struct CaseTransform: Transform {
  public enum Style: String, Sendable, CaseIterable {
    case upper
    case lower
    case title
  }

  public let style: Style
  public let requiresNetwork = false

  public var id: String { "case.\(style.rawValue)" }

  public var title: String {
    switch style {
    case .upper: return "Upper Case"
    case .lower: return "Lower Case"
    case .title: return "Title Case"
    }
  }

  public init(_ style: Style) {
    self.style = style
  }

  public func applicability(to input: TransformInput) -> Applicability {
    TextPredicate.hasText(input)
  }

  public func apply(to input: TransformInput) async throws -> TransformOutput {
    switch style {
    case .upper: return .plainText(input.plainText.localizedUppercase)
    case .lower: return .plainText(input.plainText.localizedLowercase)
    case .title: return .plainText(Self.titleCased(input.plainText))
    }
  }

  /// The conservative rule §7.2 asks for: raise the first letter of each word
  /// and leave every other character alone.
  ///
  /// `localizedCapitalized` would lower the rest, which turns `JSON` into `Json`
  /// and `McDonald` into `Mcdonald`. Since a word list is explicitly ruled out,
  /// the honest choice is the rule that destroys the least — someone who wanted
  /// the acronym lowered can ask for lower case first.
  internal static func titleCased(_ text: String) -> String {
    var result = ""
    result.reserveCapacity(text.count)
    var atWordStart = true
    for character in text {
      if character.isLetter || character.isNumber {
        result += atWordStart ? String(character).localizedUppercase : String(character)
        atWordStart = false
      } else {
        result.append(character)
        atWordStart = true
      }
    }
    return result
  }
}

/// Trailing whitespace per line, plus leading and trailing whitespace overall
/// (§7.2).
public struct WhitespaceTrimTransform: Transform {
  public let id = "whitespace.trim"
  public let title = "Trim Whitespace"
  public let requiresNetwork = false

  public init() {}

  /// The one transform that does not use `TextPredicate`, since whitespace-only
  /// text is exactly what it exists to deal with. It declines instead when
  /// there is nothing it would change, so that it is not offered as a no-op.
  public func applicability(to input: TransformInput) -> Applicability {
    guard !input.plainText.isEmpty else {
      return .notApplicable(reason: "There is no text to transform.")
    }
    guard Self.trimmed(input.plainText) != input.plainText else {
      return .notApplicable(reason: "There is no stray whitespace to trim.")
    }
    return .applicable
  }

  public func apply(to input: TransformInput) async throws -> TransformOutput {
    .plainText(Self.trimmed(input.plainText))
  }

  /// Line breaks are preserved as they were found, so that a file with CRLF
  /// endings does not silently acquire LF ones.
  internal static func trimmed(_ text: String) -> String {
    let lines = text.components(separatedBy: "\n")
    let trimmed = lines.map { line -> String in
      let hasReturn = line.hasSuffix("\r")
      let body = hasReturn ? String(line.dropLast()) : line
      var index = body.endIndex
      while index > body.startIndex {
        let previous = body.index(before: index)
        guard body[previous] == " " || body[previous] == "\t" else { break }
        index = previous
      }
      return String(body[body.startIndex..<index]) + (hasReturn ? "\r" : "")
    }
    return trimmed.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
  }
}

/// Sorts lines ascending, stably, with a localised comparison (§7.2).
public struct SortLinesTransform: Transform {
  public let id = "lines.sort"
  public let title = "Sort Lines"
  public let requiresNetwork = false

  public init() {}

  public func applicability(to input: TransformInput) -> Applicability {
    guard case .applicable = TextPredicate.hasText(input) else {
      return .notApplicable(reason: "There is no text to transform.")
    }
    guard input.plainText.components(separatedBy: .newlines).count >= 2 else {
      return .notApplicable(reason: "Sorting needs at least two lines.")
    }
    return .applicable
  }

  public func apply(to input: TransformInput) async throws -> TransformOutput {
    let lines = input.plainText.components(separatedBy: "\n")
    // `sorted(by:)` is not guaranteed stable, and §7.2 asks for stability, so
    // the original position breaks every tie explicitly.
    let sorted =
      lines.enumerated()
      .sorted { left, right in
        let order = left.element.localizedCompare(right.element)
        return order == .orderedSame ? left.offset < right.offset : order == .orderedAscending
      }
      .map(\.element)
    return .plainText(sorted.joined(separator: "\n"))
  }
}
