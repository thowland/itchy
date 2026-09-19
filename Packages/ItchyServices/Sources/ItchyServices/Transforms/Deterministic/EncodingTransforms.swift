import Foundation
import ItchyCore

/// Base64, UTF-8, without line breaks (§7.2).
public struct Base64EncodeTransform: Transform {
  public let id = "base64.encode"
  public let title = "Encode Base64"
  public let requiresNetwork = false

  public init() {}

  public func applicability(to input: TransformInput) -> Applicability {
    TextPredicate.hasText(input)
  }

  public func apply(to input: TransformInput) async throws -> TransformOutput {
    guard let data = input.plainText.data(using: .utf8) else {
      throw TransformError.failed(reason: "The text could not be read as UTF-8.")
    }
    return .plainText(data.base64EncodedString())
  }
}

/// Decodes base64, but only when the result is text (§7.2).
///
/// Both conditions matter. Valid base64 that decodes to arbitrary bytes would
/// put mojibake in the pad, and the transform would have offered itself to do
/// it — so the predicate decodes, and declines when the bytes are not UTF-8.
public struct Base64DecodeTransform: Transform {
  public let id = "base64.decode"
  public let title = "Decode Base64"
  public let requiresNetwork = false

  public init() {}

  public func applicability(to input: TransformInput) -> Applicability {
    guard case .applicable = TextPredicate.hasText(input) else {
      return .notApplicable(reason: "There is no text to transform.")
    }
    guard Self.decoded(input.plainText) != nil else {
      return .notApplicable(reason: "This is not base64 that decodes to text.")
    }
    return .applicable
  }

  public func apply(to input: TransformInput) async throws -> TransformOutput {
    guard let text = Self.decoded(input.plainText) else {
      throw TransformError.failed(reason: "This is not base64 that decodes to text.")
    }
    return .plainText(text)
  }

  /// Surrounding whitespace is ignored, because base64 arrives wrapped as often
  /// as not, but the decode itself rejects any other stray character rather than
  /// guessing. `Data(base64Encoded:)` accepts a truncated final group, so the
  /// length is checked first.
  internal static func decoded(_ text: String) -> String? {
    let compacted = text.components(separatedBy: .whitespacesAndNewlines).joined()
    guard !compacted.isEmpty, compacted.count % 4 == 0 else { return nil }
    guard let data = Data(base64Encoded: compacted) else { return nil }
    return String(data: data, encoding: .utf8)
  }
}

/// Percent-encodes as a URL *component*, not as a whole URL (§7.2).
///
/// Component encoding is the useful one: someone with a query value in a pad
/// wants `&` and `=` encoded, and whole-URL encoding would leave them alone and
/// produce something that silently means a different request. The allowed set is
/// RFC 3986's unreserved characters, which is narrower than any of Foundation's
/// stock sets.
public struct URLEncodeTransform: Transform {
  public let id = "url.encode"
  public let title = "Encode URL Component"
  public let requiresNetwork = false

  internal static let unreserved = CharacterSet(charactersIn: "ABCDEFGHIJKLMNOPQRSTUVWXYZ")
    .union(CharacterSet(charactersIn: "abcdefghijklmnopqrstuvwxyz"))
    .union(CharacterSet(charactersIn: "0123456789-._~"))

  public init() {}

  public func applicability(to input: TransformInput) -> Applicability {
    TextPredicate.hasText(input)
  }

  public func apply(to input: TransformInput) async throws -> TransformOutput {
    guard let encoded = input.plainText.addingPercentEncoding(withAllowedCharacters: Self.unreserved)
    else {
      throw TransformError.failed(reason: "The text could not be percent-encoded.")
    }
    return .plainText(encoded)
  }
}

/// Decodes percent-encoding, when the text actually carries some (§7.2).
public struct URLDecodeTransform: Transform {
  public let id = "url.decode"
  public let title = "Decode URL Component"
  public let requiresNetwork = false

  public init() {}

  /// Declines text with no `%` in it at all, which would otherwise decode to
  /// itself and offer a menu item that does nothing.
  public func applicability(to input: TransformInput) -> Applicability {
    guard case .applicable = TextPredicate.hasText(input) else {
      return .notApplicable(reason: "There is no text to transform.")
    }
    guard input.plainText.contains("%") else {
      return .notApplicable(reason: "This text holds no percent-encoding.")
    }
    guard input.plainText.removingPercentEncoding != nil else {
      return .notApplicable(reason: "This is not valid percent-encoding.")
    }
    return .applicable
  }

  public func apply(to input: TransformInput) async throws -> TransformOutput {
    guard let decoded = input.plainText.removingPercentEncoding else {
      throw TransformError.failed(reason: "This is not valid percent-encoding.")
    }
    return .plainText(decoded)
  }
}
